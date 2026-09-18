#!/usr/bin/env python3
"""Extract token/cost usage from an rsi-loop round execution trace.

Usage:
  trace-usage.py <trace-path> [--pricing FILE]

<trace-path> is one of:
  - a pi session JSONL file: assistant "message" events carry
    usage{input, output, cacheRead, cacheWrite, reasoning, totalTokens,
    cost{input, output, cacheRead, cacheWrite, total}} (native cost);
  - a kimi session directory containing wire.jsonl: StatusUpdate events
    carry payload.token_usage{input_other, output, input_cache_read,
    input_cache_creation} (no cost, no model id);
  - a kimi wire.jsonl file path directly;
  - anything else: reported as agent "unknown" with null metrics —
    never guessed.

Cost is resolved in this order:
  native      sum of the trace's own per-message cost (pi);
  pricing     tokens x rates from --pricing FILE ($/Mtok, "default" key;
              needed for traces without native cost, e.g. kimi);
  none        not computable -> cost_usd: null.

Output: one JSON object on stdout:
  {"agent", "requests", "tokens": {input, output, cache_read, cache_write,
   reasoning}, "total_tokens", "cost_usd", "cost_source"}

Exit codes: 0 = ok (including unknown format), 2 = usage error or
unreadable path. Read-only: never modifies the trace.
"""

import argparse
import json
import os
import sys

TOKEN_KEYS = ("input", "output", "cache_read", "cache_write", "reasoning")


def _iter_jsonl(path):
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(obj, dict):
                yield obj


def _blank_tokens():
    return {k: 0 for k in TOKEN_KEYS}


def _parse_pi(path):
    tokens = _blank_tokens()
    total = 0.0
    cost = 0.0
    requests = 0
    has_cost = False
    for obj in _iter_jsonl(path):
        msg = obj.get("message")
        if not isinstance(msg, dict):
            continue
        usage = msg.get("usage")
        if not isinstance(usage, dict):
            continue
        requests += 1
        tokens["input"] += usage.get("input") or 0
        tokens["output"] += usage.get("output") or 0
        tokens["cache_read"] += usage.get("cacheRead") or 0
        tokens["cache_write"] += usage.get("cacheWrite") or 0
        tokens["reasoning"] += usage.get("reasoning") or 0
        total += usage.get("totalTokens") or 0
        c = usage.get("cost")
        if isinstance(c, dict) and c.get("total") is not None:
            has_cost = True
            cost += c.get("total") or 0
    if requests == 0:
        return None
    return {
        "agent": "pi",
        "requests": requests,
        "tokens": tokens,
        "total_tokens": int(total),
        "cost_usd": round(cost, 6) if has_cost else None,
        "cost_source": "native" if has_cost else None,
    }


def _parse_kimi(path):
    tokens = _blank_tokens()
    total = 0
    requests = 0
    for obj in _iter_jsonl(path):
        msg = obj.get("message")
        if not isinstance(msg, dict) or msg.get("type") != "StatusUpdate":
            continue
        payload = msg.get("payload")
        tu = payload.get("token_usage") if isinstance(payload, dict) else None
        if not isinstance(tu, dict):
            continue
        requests += 1
        tokens["input"] += tu.get("input_other") or 0
        tokens["output"] += tu.get("output") or 0
        tokens["cache_read"] += tu.get("input_cache_read") or 0
        tokens["cache_write"] += tu.get("input_cache_creation") or 0
    if requests == 0:
        return None
    total = sum(tokens[k] for k in TOKEN_KEYS)
    return {
        "agent": "kimi",
        "requests": requests,
        "tokens": tokens,
        "total_tokens": int(total),
        "cost_usd": None,
        "cost_source": None,
    }


def _looks_kimi(path):
    for obj in _iter_jsonl(path):
        msg = obj.get("message")
        if isinstance(msg, dict) and msg.get("type") == "StatusUpdate":
            payload = msg.get("payload")
            if isinstance(payload, dict) and isinstance(payload.get("token_usage"), dict):
                return True
    return False


def load_pricing(path):
    """Load $/Mtok rates from a policy-style YAML file.

    Accepts either a flat {input, output, cache_read, cache_write} map or a
    policy file with a `pricing:` section holding a `default` map.
    """
    try:
        import yaml
    except ImportError:
        sys.exit("trace-usage.py: --pricing needs PyYAML (pip install pyyaml)")
    with open(path, "r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    rates = data.get("pricing", data)
    if isinstance(rates, dict):
        rates = rates.get("default", rates)
    if not isinstance(rates, dict):
        sys.exit("trace-usage.py: pricing file has no usable rate map")
    return {k: float(rates.get(k) or 0) for k in
            ("input", "output", "cache_read", "cache_write")}


def _apply_pricing(result, rates):
    t = result["tokens"]
    cost = (t["input"] * rates["input"]
            + t["output"] * rates["output"]
            + t["cache_read"] * rates["cache_read"]
            + t["cache_write"] * rates["cache_write"]) / 1_000_000
    result["cost_usd"] = round(cost, 6)
    result["cost_source"] = "pricing"


def extract(path, pricing=None):
    """Extract usage from a trace path. Returns the report dict."""
    if os.path.isdir(path):
        wire = os.path.join(path, "wire.jsonl")
        if os.path.isfile(wire):
            result = _parse_kimi(wire)
        else:
            result = None
    elif os.path.isfile(path):
        result = _parse_pi(path)
        if result is None:
            result = _parse_kimi(path)
        elif _looks_kimi(path):
            result = _parse_kimi(path)
    else:
        result = None

    if result is None:
        return {
            "agent": "unknown",
            "requests": 0,
            "tokens": None,
            "total_tokens": None,
            "cost_usd": None,
            "cost_source": "none",
        }
    if result["cost_usd"] is None and pricing:
        _apply_pricing(result, pricing)
    if result["cost_source"] is None:
        result["cost_source"] = "none"
    return result


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("trace", help="trace file (pi JSONL / kimi wire.jsonl) or session dir")
    ap.add_argument("--pricing", help="policy YAML with $/Mtok rates for traces without native cost")
    args = ap.parse_args(argv)

    if not os.path.exists(args.trace):
        print(f"trace-usage.py: no such path: {args.trace}", file=sys.stderr)
        return 2
    pricing = load_pricing(args.pricing) if args.pricing else None
    print(json.dumps(extract(args.trace, pricing), indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
