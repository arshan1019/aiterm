"""Batch plan for incremental fine-tuning.

Examples are grouped into length buckets (multiples of 64 tokens) so each
batch is padded only to its own bucket instead of the longest example in the
set: most of our examples are far shorter than the longest, so padding
everything to it spent most of the compute on padding. Every batch is full
(small buckets repeat examples), keeping the number of compiled shapes to
one per bucket. The plan is a pure function of (lengths, batch, epochs,
seed), so a resumed run picks up at step N of exactly the same sequence.
"""
import random


def bucket_of(length, step=64, floor=128, cap=512):
    size = max(floor, -(-length // step) * step)
    return min(size, cap)


def make_plan(lengths, batch, epochs, seed, cap=512):
    buckets = {}
    for i, n in enumerate(lengths):
        buckets.setdefault(bucket_of(n, cap=cap), []).append(i)
    plan = []
    for epoch in range(epochs):
        rng = random.Random(seed * 1000 + epoch)
        epoch_batches = []
        for size in sorted(buckets):
            members = buckets[size][:]
            rng.shuffle(members)
            for start in range(0, len(members), batch):
                chunk = members[start:start + batch]
                k = 0
                while len(chunk) < batch:  # fill from the same bucket
                    chunk.append(members[k % len(members)])
                    k += 1
                epoch_batches.append(chunk)
        rng.shuffle(epoch_batches)
        plan.extend(epoch_batches)
    return plan
