#!/usr/bin/env bash
set -euo pipefail
TARGET="${1:?usage: setup.sh <target-dir>}"
mkdir -p "$TARGET"

cat > "$TARGET/events.py" <<'EOF'
"""简单事件处理：注册的处理器依次处理每个事件。"""

_HANDLERS = []


def handler_log(event):
    return f"logged:{event}"


def handler_audit(event):
    return f"audited:{event}"


def register_defaults():
    _HANDLERS.append(handler_log)
    _HANDLERS.append(handler_audit)


def process(events):
    register_defaults()
    return [h(e) for e in events for h in _HANDLERS]
EOF

cat > "$TARGET/test_events.py" <<'EOF'
import unittest

import events


class TestEvents(unittest.TestCase):
    def test_process_once(self):
        result = events.process(["a", "b"])
        self.assertEqual(
            result,
            ["logged:a", "audited:a", "logged:b", "audited:b"],
        )


if __name__ == "__main__":
    unittest.main()
EOF
