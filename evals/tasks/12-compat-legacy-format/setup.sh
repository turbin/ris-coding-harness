#!/usr/bin/env bash
# Creates the initial (buggy) project in $1.
set -euo pipefail
cat > "$1/records.py" <<'PY'
"""Tiny record serialization."""

import json


def serialize(record):
    return json.dumps({"name": record["name"], "region": record.get("region", "")})


def parse(text):
    data = json.loads(text)
    return {"name": data["name"], "region": data["region"]}  # crashes on legacy
PY
