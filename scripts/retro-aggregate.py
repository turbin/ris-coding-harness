#!/usr/bin/env python3
"""Aggregate RSI review verdicts (evals/results/*.yaml) into retro input.

Usage:
  retro-aggregate.py [verdicts-dir] [--verbose]

Reads every `<task-id>-<milestone>.yaml` in the verdicts directory
(evals/results by default), aggregates by issue category and severity,
and prints the data summary that feeds a retro report (docs/rsi-design.md
§4.3). Does not modify any file.

Exit codes: 0 = ok (even with no verdicts), 2 = usage error.
"""

import argparse
import collections
import glob
import os
import sys

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.exit("retro-aggregate.py needs PyYAML (pip install pyyaml)")

CATEGORIES = [
    "correctness", "testing", "simplicity", "resource",
    "concurrency", "compatibility", "convention", "scope",
]
SEVERITIES = ["BLOCKER", "MAJOR", "MINOR", "NIT"]


def load_verdicts(path):
    verdicts = []
    for f in sorted(glob.glob(os.path.join(path, "*.yaml"))):
        with open(f, encoding="utf-8") as fh:
            doc = yaml.safe_load(fh)
        if not isinstance(doc, dict) or doc.get("schema_version") != 1:
            print(f"skip (not schema v1): {os.path.basename(f)}", file=sys.stderr)
            continue
        doc["_file"] = os.path.basename(f)
        verdicts.append(doc)
    return verdicts


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("verdicts_dir", nargs="?", default="evals/results")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    verdicts = load_verdicts(args.verdicts_dir)
    if not verdicts:
        print(f"no verdicts found in {args.verdicts_dir}")
        return 0

    # --- per-task table -------------------------------------------------
    print("task                                   decision  rounds  red  issues")
    for v in verdicts:
        red = "yes" if v.get("coder_red_green_evidence") else "no"
        print(f"{v['task_id']:<38} {v['decision']:<9} "
              f"{v.get('rounds', 0):<7} {red:<4} {len(v.get('issues', []))}")

    # --- aggregates ------------------------------------------------------
    cat_sev = collections.Counter()
    accepted = sum(1 for v in verdicts if v["decision"] == "accepted")
    total = len(verdicts)
    rounds = [v.get("rounds", 1) for v in verdicts]
    no_red = sum(1 for v in verdicts if not v.get("coder_red_green_evidence"))
    issues = [i for v in verdicts for i in v.get("issues", [])]
    for i in issues:
        cat_sev[(i.get("category"), i.get("severity"))] += 1

    print()
    print(f"verdicts: {total}   accepted: {accepted} ({accepted/total:.0%})   "
          f"avg rounds: {sum(rounds)/len(rounds):.2f}   "
          f"no-RED milestones: {no_red} ({no_red/total:.0%})")

    print()
    print("issues by category x severity:")
    print(f"{'category':<14}" + "".join(f"{s:>9}" for s in SEVERITIES) + f"{'total':>7}")
    for cat in CATEGORIES:
        row = [cat_sev[(cat, s)] for s in SEVERITIES]
        if sum(row) == 0 and not args.verbose:
            continue
        print(f"{cat:<14}" + "".join(f"{n:>9}" for n in row) + f"{sum(row):>7}")

    if args.verbose:
        print()
        print("all findings:")
        for v in verdicts:
            for i in v.get("issues", []):
                print(f"- [{i.get('severity')}/{i.get('category')}] "
                      f"{v['task_id']}: {i.get('summary')}")

    # --- recurring-pattern hints -----------------------------------------
    print()
    print("recurring hints (category with >=2 findings):")
    for cat in CATEGORIES:
        n = sum(cat_sev[(cat, s)] for s in SEVERITIES)
        if n >= 2:
            print(f"  {cat}: {n} findings")
    return 0


if __name__ == "__main__":
    sys.exit(main())
