#!/usr/bin/env python3
"""Scores a Needle model on an eval set using the real engine (the needle CLI's
HTTP server) and the full tool list the app sends.

  python3 training/eval.py --needle ./needle --model tuned.cact --cases training/holdout.tsv
"""
import argparse, json, os, subprocess, time, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--needle", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--cases", required=True)
    ap.add_argument("--tools", default=os.path.join(HERE, "..", "assets", "needle_tools.json"))
    ap.add_argument("--port", default="8090")
    args = ap.parse_args()
    base = f"http://127.0.0.1:{args.port}"
    server = subprocess.Popen([args.needle, "--model", args.model, "--tools", args.tools,
                               "--serve", "--port", args.port],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def post(path, body):
        req = urllib.request.Request(base + path, json.dumps(body).encode(),
                                     {"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read() or b"{}")

    try:
        for _ in range(180):
            try:
                post("/reset", {}); break
            except Exception:
                time.sleep(1)
        cases = [l.rstrip("\n").split("\t") for l in open(args.cases)
                 if l.strip() and not l.startswith("#")]
        ok, fails = 0, []
        for c in cases:
            prompt, want = c[0], c[1]
            checks = [kv.split("=", 1) for kv in c[2].split(",")] if len(c) > 2 and c[2] else []
            post("/reset", {})
            calls = post("/complete", {"input": prompt}).get("function_calls") or []
            if want == "NONE":
                good = not calls
            else:
                good = bool(calls) and calls[0]["name"] == want and all(
                    v.lower() in str(calls[0]["arguments"].get(k, "")).lower() for k, v in checks)
            ok += good
            if not good:
                got = [(x["name"], x["arguments"]) for x in calls] or "nothing"
                fails.append(f"  {prompt!r}: want {want} {c[2] if len(c) > 2 else ''} | got {got}")
        print(f"{os.path.basename(args.model)} on {os.path.basename(args.cases)}: "
              f"{ok}/{len(cases)} = {100 * ok / len(cases):.0f}%")
        print("\n".join(fails))
    finally:
        server.terminate()

if __name__ == "__main__":
    main()
