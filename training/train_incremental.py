"""Incremental, time-boxed LoRA fine-tuning for Needle.

`needle finetune` trains in one go, pads every example to the longest one
and scores itself by slow decoding at the end; on a 4-core CI runner our set
didn't finish within GitHub's job limit and the work was lost. This driver
reuses Needle's own model, quantisation (CQ W-bit STE + A8, matching the
exported archive) and LoRA code, and adds:

  * resume: lora + optimizer state + step are saved to --state, and a run
    continues exactly where the last one stopped (see plan.py);
  * a time budget: it stops cleanly before the job limit, and also writes a
    checkpoint every --save-minutes in case the job is killed;
  * length buckets: batches pad to a multiple of 64, not the longest example;
  * a persistent JAX compile cache, so later runs don't recompile.

Exit status is 0 whether finished or not; state/progress.json says which.
"""
import argparse
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
from plan import bucket_of, make_plan  # noqa: E402


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--data", required=True)
    p.add_argument("--state", required=True, help="checkpoint directory (read and written)")
    p.add_argument("--out", default="adapter.safetensors", help="final adapter, written when done")
    p.add_argument("--epochs", type=int, default=2)
    p.add_argument("--batch-size", type=int, default=16)
    p.add_argument("--lr", type=float, default=1e-4)
    p.add_argument("--rank", type=int, default=16)
    p.add_argument("--alpha", type=float, default=32.0)
    p.add_argument("--max-len", type=int, default=512)
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--budget-minutes", type=float, default=300)
    p.add_argument("--save-minutes", type=float, default=15)
    args = p.parse_args()
    started = time.time()

    import jax
    import jax.numpy as jnp
    import numpy as np
    import optax
    from flax import serialization
    from needle.model.architecture import SimpleAttentionNetwork
    from needle.model.checkpoints import write_adapter
    from needle.model.finetune import DEFAULT_BASE, init_lora, lora_target_paths, read_examples, render_example
    from needle.model.quantize import WEIGHT_BITS, configure_deploy, cq_ste_params
    from needle.model.run import load_checkpoint
    from needle.model.tokenizer import BOS_ID, EOS_ID, PAD_ID, get_tokenizer

    cache = os.environ.get("JAX_CACHE_DIR")
    if cache:
        jax.config.update("jax_compilation_cache_dir", cache)
        jax.config.update("jax_persistent_cache_min_compile_time_secs", 0)

    def log(msg):
        print(f"[{(time.time() - started) / 60:6.1f}m] {msg}", flush=True)

    # ── Model ──────────────────────────────────────────────────────────
    params, config = load_checkpoint(DEFAULT_BASE)
    config.dtype = "float32"
    params = jax.device_put(jax.tree.map(lambda a: np.asarray(a).astype(np.float32), params))
    model = SimpleAttentionNetwork(config)
    configure_deploy(act_bits=getattr(config, "act_bits", 8), kv_bits=getattr(config, "kv_bits", 8))
    tokenizer = get_tokenizer(config.vocab_size)

    # ── Data: token ids with a loss mask on the answer only ────────────
    seqs, masks = [], []
    for ex in read_examples(args.data):
        prompt, target = render_example(ex)
        pi, ti = tokenizer.encode(prompt), tokenizer.encode(target)
        ids = ([BOS_ID] + pi + ti + [EOS_ID])[: args.max_len]
        mask = ([0.0] * (1 + len(pi)) + [1.0] * (len(ti) + 1))[: args.max_len]
        seqs.append(ids)
        masks.append(mask)
    lengths = [len(s) for s in seqs]
    plan = make_plan(lengths, args.batch_size, args.epochs, args.seed, cap=args.max_len)
    total = len(plan)
    padded_flat = len(seqs) * bucket_of(max(lengths), cap=args.max_len)
    padded_buckets = sum(bucket_of(n, cap=args.max_len) for n in lengths)
    log(f"data {len(seqs)} examples, lengths median {sorted(lengths)[len(lengths) // 2]} max {max(lengths)}; "
        f"padding tokens {padded_flat} → {padded_buckets} with buckets (x{padded_flat / padded_buckets:.2f} less work)")

    def batch_arrays(idx):
        width = bucket_of(max(lengths[i] for i in idx), cap=args.max_len)
        ids = np.full((len(idx), width), PAD_ID, np.int32)
        msk = np.zeros((len(idx), width), np.float32)
        for row, i in enumerate(idx):
            ids[row, : lengths[i]] = seqs[i]
            msk[row, : lengths[i]] = masks[i]
        return jnp.asarray(ids), jnp.asarray(msk)

    # ── LoRA, optimizer, and resume ────────────────────────────────────
    paths = lora_target_paths(params)
    key_of = {"/".join(p): p for p in paths}
    lora = {"/".join(p): v for p, v in init_lora(params, paths, args.rank, jax.random.PRNGKey(args.seed)).items()}
    scale = args.alpha / args.rank
    warmup = min(max(1, total // 20), total - 1)
    schedule = optax.warmup_cosine_decay_schedule(0.0, args.lr, warmup_steps=warmup, decay_steps=total)
    optimizer = optax.chain(optax.clip_by_global_norm(1.0), optax.adamw(schedule))
    opt_state = optimizer.init(lora)
    step = 0

    os.makedirs(args.state, exist_ok=True)
    ckpt_path = os.path.join(args.state, "checkpoint.msgpack")
    progress_path = os.path.join(args.state, "progress.json")
    if os.path.exists(ckpt_path):
        restored = serialization.from_bytes({"lora": lora, "opt": opt_state, "step": 0}, open(ckpt_path, "rb").read())
        lora, opt_state, step = restored["lora"], restored["opt"], int(restored["step"])
        log(f"resumed at step {step}/{total}")
    else:
        log(f"starting: {total} steps ({args.epochs} epochs), batch {args.batch_size}, rank {args.rank}")

    def save(done):
        tmp = ckpt_path + ".tmp"
        with open(tmp, "wb") as f:
            f.write(serialization.to_bytes({"lora": lora, "opt": opt_state, "step": step}))
        os.replace(tmp, ckpt_path)
        with open(progress_path, "w") as f:
            json.dump({"step": step, "total": total, "done": done, "epochs": args.epochs}, f)
        log(f"saved step {step}/{total}{' (done)' if done else ''}")

    # ── Training ───────────────────────────────────────────────────────
    def merged(lora):
        flat = dict(__import__("flax").traverse_util.flatten_dict(params))
        for name, ab in lora.items():
            path = key_of[name]
            flat[path] = flat[path] + (scale * jnp.matmul(ab["A"], ab["B"])).astype(flat[path].dtype)
        return __import__("flax").traverse_util.unflatten_dict(flat)

    def loss_fn(lora, ids, mask):
        weights = cq_ste_params(merged(lora), WEIGHT_BITS)
        logits = model.apply({"params": weights}, ids, quant=True)
        logits, targets, mask = logits[:, :-1], ids[:, 1:], mask[:, 1:]
        ce = optax.softmax_cross_entropy_with_integer_labels(logits, targets)
        return (ce * mask).sum() / jnp.maximum(mask.sum(), 1.0)

    @jax.jit
    def train_step(lora, opt_state, ids, mask):
        loss, grads = jax.value_and_grad(loss_fn)(lora, ids, mask)
        updates, opt_state = optimizer.update(grads, opt_state, lora)
        return optax.apply_updates(lora, updates), opt_state, loss

    budget = args.budget_minutes * 60
    last_save = time.time()
    window, window_start, losses = 0, time.time(), []
    while step < total:
        if time.time() - started > budget:
            log("time budget reached")
            break
        lora, opt_state, loss = train_step(lora, opt_state, *batch_arrays(plan[step]))
        step += 1
        window += 1
        losses.append(float(loss))
        if step % 10 == 0 or step == total:
            rate = (time.time() - window_start) / window
            log(f"step {step}/{total}  loss {np.mean(losses[-10:]):.4f}  {rate:.1f}s/step  "
                f"eta {(total - step) * rate / 3600:.1f}h")
            window, window_start = 0, time.time()
        if time.time() - last_save > args.save_minutes * 60:
            save(False)
            last_save = time.time()

    done = step >= total
    save(done)
    if done:
        write_adapter(args.out, {
            "lora": {name: {"A": np.asarray(v["A"]), "B": np.asarray(v["B"])} for name, v in lora.items()},
            "scale": float(scale),
            "base": DEFAULT_BASE,
            "rank": args.rank,
            "seed": args.seed,
        })
        log(f"adapter written: {args.out}")


if __name__ == "__main__":
    main()
