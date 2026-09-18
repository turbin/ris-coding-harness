#!/usr/bin/env python3
"""Aggregate RSI review verdicts (evals/results/*.yaml) into retro input.

Usage:
  retro-aggregate.py [verdicts-dir] [--verbose]

Reads every `<task-id>-<milestone>.yaml` in the verdicts directory
(evals/results by default), aggregates by issue category and severity,
and prints the data summary that feeds a retro report (docs/rsi-design.md
§4.3). Does not modify any file.

With `--rounds-dir` (default `progress/loop`), loop round reports are also
aggregated for budget telemetry (§4.8): per-task budget vs actual
tokens/cost, overruns, and cumulative totals. Round reports without budget
fields (pre-§4.8 rounds) are reported as unmetered, not errors; YAML parse
errors fail loud like verdict errors.

Validation (P4, retro-2026-08-29): every verdict file is parsed and
schema-checked BEFORE aggregation. Any YAML parse error or schema violation
is reported with file name and location; aggregation is aborted (exit 2)
listing ALL invalid files — the telemetry pipeline fails loud, not silent.
Origin grouping (P5, retro-2026-08-29): `origin` (protocol|manual) is
optional for backward compatibility; when present, RED/pass statistics are
also reported per origin so protocol rounds and manual bookkeeping verdicts
never mix.

Exit codes: 0 = ok (even with no verdicts), 2 = usage error or invalid data.
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
SCORE_KEYS = ["correctness", "test_quality", "simplicity",
              "resource_safety", "convention_fit"]
ORIGINS = ["protocol", "manual"]
REQUIRED = ["task_id", "milestone", "decision", "scores", "issues",
            "rounds", "coder_red_green_evidence", "loc_delta",
            "new_dependencies", "timestamp"]


def check_schema(doc, fname, errors):
    """Append human-readable schema violations for one verdict to errors."""
    def err(msg, loc=""):
        errors.append(f"{fname}: {msg}{(' (' + loc + ')') if loc else ''}")

    if not isinstance(doc, dict):
        err("document is not a YAML mapping")
        return
    if doc.get("schema_version") != 1:
        err(f"schema_version must be 1, got {doc.get('schema_version')!r}",
            "top level")
        return
    for field in REQUIRED:
        if field not in doc:
            err(f"missing required field '{field}'", "top level")
    if "task_id" in doc and not isinstance(doc["task_id"], str):
        err("task_id must be a string", "task_id")
    if "milestone" in doc and not isinstance(doc["milestone"], str):
        err("milestone must be a string", "milestone")
    if doc.get("decision") not in ("accepted", "rejected"):
        err(f"decision must be accepted|rejected, got {doc.get('decision')!r}",
            "decision")
    if doc.get("origin") is not None and doc["origin"] not in ORIGINS:
        err(f"origin must be protocol|manual, got {doc['origin']!r}",
            "origin (optional)")
    scores = doc.get("scores")
    if not isinstance(scores, dict):
        err("scores must be a mapping of 5 dimensions", "scores")
    else:
        for k in SCORE_KEYS:
            if k not in scores:
                err(f"scores missing dimension '{k}'", "scores")
            elif not isinstance(scores.get(k), int) or not 1 <= scores[k] <= 5:
                err(f"score '{k}' must be an int in 1..5, got {scores.get(k)!r}",
                    f"scores.{k}")
        for k in scores:
            if k not in SCORE_KEYS:
                err(f"unknown score dimension '{k}'", "scores")
    issues = doc.get("issues")
    if not isinstance(issues, list):
        err("issues must be a list", "issues")
    else:
        for idx, i in enumerate(issues):
            loc = f"issues[{idx}]"
            if not isinstance(i, dict):
                err(f"issue entry must be a mapping", loc)
                continue
            if i.get("severity") not in SEVERITIES:
                err(f"severity must be one of {SEVERITIES}, "
                    f"got {i.get('severity')!r}", loc)
            if i.get("category") not in CATEGORIES:
                err(f"category must be one of {CATEGORIES}, "
                    f"got {i.get('category')!r}", loc)
            if not isinstance(i.get("summary"), str) or not i["summary"]:
                err("summary must be a non-empty string", loc)
    if not isinstance(doc.get("rounds"), int) or doc.get("rounds", 0) < 1:
        err(f"rounds must be an int >= 1, got {doc.get('rounds')!r}", "rounds")
    if not isinstance(doc.get("coder_red_green_evidence"), bool):
        err("coder_red_green_evidence must be a boolean",
            "coder_red_green_evidence")
    ld = doc.get("loc_delta")
    if not isinstance(ld, dict) or not all(
            isinstance(ld.get(k), int) for k in ("added", "removed")):
        err("loc_delta must be {added: <int>, removed: <int>}", "loc_delta")
    if not isinstance(doc.get("new_dependencies"), int):
        err("new_dependencies must be an int", "new_dependencies")
    if not isinstance(doc.get("timestamp"), str) or not doc["timestamp"]:
        err("timestamp must be a non-empty ISO 8601 string", "timestamp")


def load_verdicts(path):
    """Parse and schema-check every verdict; fail loud with ALL problems."""
    files = sorted(glob.glob(os.path.join(path, "*.yaml")))
    errors = []
    verdicts = []
    for f in files:
        fname = os.path.basename(f)
        before = len(errors)
        try:
            with open(f, encoding="utf-8") as fh:
                doc = yaml.safe_load(fh)
        except yaml.YAMLError as e:
            mark = getattr(e, "problem_mark", None)
            loc = (f"line {mark.line + 1}, col {mark.column + 1}" if mark
                   else "unknown location")
            errors.append(f"{fname}: YAML parse error at {loc}: {e.problem}")
            continue
        check_schema(doc, fname, errors)
        if len(errors) == before:  # this file is clean
            doc["_file"] = fname
            verdicts.append(doc)
    if errors:
        print(f"INVALID VERDICT DATA ({len(errors)} problem(s), "
              f"{len(files)} file(s) checked):", file=sys.stderr)
        for e in errors:
            print(f"  {e}", file=sys.stderr)
        print("Fix the verdicts above (schema v1, see "
              "skills/pm-workers-engineering/references/verdict-schema.md), "
              "then re-run. Aggregation aborted.", file=sys.stderr)
        sys.exit(2)
    return verdicts


def origin_stats(verdicts, origin):
    sub = [v for v in verdicts if v.get("origin", "manual") == origin]
    if not sub:
        return None
    accepted = sum(1 for v in sub if v["decision"] == "accepted")
    no_red = sum(1 for v in sub if not v.get("coder_red_green_evidence"))
    return (len(sub), accepted, no_red)


def load_rounds(path):
    """Load loop round reports for budget telemetry; fail loud on parse errors."""
    if not os.path.isdir(path):
        return None
    files = sorted(glob.glob(os.path.join(path, "round-*.yaml")))
    if not files:
        return None
    rounds, errors = [], []
    for f in files:
        fname = os.path.basename(f)
        try:
            with open(f, encoding="utf-8") as fh:
                doc = yaml.safe_load(fh)
        except yaml.YAMLError as e:
            mark = getattr(e, "problem_mark", None)
            loc = (f"line {mark.line + 1}, col {mark.column + 1}" if mark
                   else "unknown location")
            errors.append(f"{fname}: YAML parse error at {loc}: {e.problem}")
            continue
        if isinstance(doc, dict) and doc.get("task_id"):
            doc["_file"] = fname
            rounds.append(doc)
    if errors:
        print(f"INVALID ROUND REPORT DATA ({len(errors)} problem(s)):",
              file=sys.stderr)
        for e in errors:
            print(f"  {e}", file=sys.stderr)
        sys.exit(2)
    return rounds


def report_budget(rounds, rounds_dir):
    """Print budget telemetry (§4.8) aggregated from loop round reports."""
    metered, unmetered = [], []
    for r in rounds:
        total = r.get("total_tokens")
        if isinstance(total, int):
            metered.append(r)
        else:
            unmetered.append(r["_file"])
    if not rounds:
        return
    print()
    print(f"budget telemetry ({rounds_dir}: {len(rounds)} round report(s), "
          f"{len(metered)} metered):")
    if metered:
        print(f"{'task':<38} {'file':<18} {'budget':>9} {'total':>9} "
              f"{'exceeded':>8} {'cost_usd':>10}")
        tokens_sum = cost_sum = exceeded = 0
        for r in metered:
            budget = r.get("budget") or {}
            budget_tokens = budget.get("tokens")
            total = r["total_tokens"]
            over = r.get("budget_exceeded")
            over = ("?" if over is None else
                    "yes" if over else "no")
            cost = r.get("cost_usd")
            tokens_sum += total
            if isinstance(cost, (int, float)):
                cost_sum += cost
            if over == "yes":
                exceeded += 1
            print(f"{r['task_id']:<38} {r['_file']:<18} "
                  f"{'?' if budget_tokens is None else budget_tokens:>9} "
                  f"{total:>9} {over:>8} "
                  f"{'?' if cost is None else format(cost, '.6f'):>10}")
        print(f"totals: tokens {tokens_sum}   cost_usd {cost_sum:.6f}   "
              f"budget_exceeded rounds: {exceeded}")
    if unmetered:
        print(f"unmetered rounds (no usage data): {len(unmetered)} "
              f"({', '.join(unmetered)})")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("verdicts_dir", nargs="?", default="evals/results")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--rounds-dir", default="progress/loop", metavar="DIR",
                    help="loop round-report dir for budget telemetry "
                         "(default: progress/loop; pass an empty string to skip)")
    args = ap.parse_args()

    verdicts = load_verdicts(args.verdicts_dir)
    round_reports = load_rounds(args.rounds_dir) if args.rounds_dir else None
    if not verdicts:
        print(f"no verdicts found in {args.verdicts_dir}")
        if round_reports:
            report_budget(round_reports, args.rounds_dir)
        return 0

    # --- per-task table -------------------------------------------------
    print("task                                   origin    decision  rounds  red  issues")
    for v in verdicts:
        red = "yes" if v.get("coder_red_green_evidence") else "no"
        print(f"{v['task_id']:<38} {v.get('origin', 'manual'):<9} "
              f"{v['decision']:<9} {v.get('rounds', 0):<7} "
              f"{red:<4} {len(v.get('issues', []))}")

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

    # origin-grouped statistics (P5): protocol rounds vs manual bookkeeping
    print()
    for origin in ORIGINS:
        st = origin_stats(verdicts, origin)
        if st is None:
            continue
        n, acc, nr = st
        print(f"origin {origin:<8} verdicts: {n:<3} accepted: {acc} "
              f"({acc/n:.0%})   no-RED: {nr} ({nr/n:.0%})")

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

    if round_reports:
        report_budget(round_reports, args.rounds_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
