#!/usr/bin/env bash
# Creates the initial (over-engineered) project in $1.
set -euo pipefail
cat > "$1/pricing.py" <<'PY'
"""Pricing formatters. (Over-engineered on purpose.)"""


class _Formatter:
    prefix = ""
    scale = 1

    def format(self, value):
        return f"{self.prefix}{value * self.scale:.1f}"


class PriceFormatter(_Formatter):
    prefix = "$"
    decimals = 2

    def format(self, value):
        return f"{self.prefix}{value * self.scale:.{self.decimals}f}"


class PercentFormatter(_Formatter):
    prefix = ""
    scale = 100


class _Registry:
    def __init__(self):
        self._items = {}

    def register(self, name, factory):
        self._items[name] = factory

    def get(self, name):
        return self._items[name]


def _make_formatters():
    registry = _Registry()
    registry.register("price", PriceFormatter)
    registry.register("percent", PercentFormatter)
    return registry


_formatters = _make_formatters()


def format_price(price):
    return _formatters.get("price")().format(price)


def format_percent(ratio):
    return _formatters.get("percent")().format(ratio)
PY
