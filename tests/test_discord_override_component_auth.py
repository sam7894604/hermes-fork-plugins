"""The Discord override's button views reach upstream's ``_component_check_auth`` wherever the running
Hermes keeps it: ``plugins.platforms.discord.adapter_component_auth`` since upstream c3f3589efb
(2026-10-05), ``plugins.platforms.discord.adapter`` before. Regression for the daily-CI break first seen
on 2026-10-06 (run 37544353324): every button click raised AttributeError on hosts past that commit."""
from __future__ import annotations

import importlib
import sys

from tests.fork_plugins._plugin_loader import load_fork_plugin


def _helper_upstream_ships():
    for mod in ("plugins.platforms.discord.adapter_component_auth", "plugins.platforms.discord.adapter"):
        try:
            return getattr(importlib.import_module(mod), "_component_check_auth")
        except (ImportError, AttributeError):
            continue
    raise AssertionError("upstream ships no _component_check_auth where the override knows to look")


def test_resolver_returns_the_helper_upstream_currently_ships():
    plugin = load_fork_plugin("platforms/discord")
    assert plugin.adapter._resolve_component_check_auth() is _helper_upstream_ships()


def test_resolver_falls_back_to_the_adapter_attribute_when_the_sibling_module_is_absent(monkeypatch):
    plugin = load_fork_plugin("platforms/discord")

    def sentinel(interaction, allowed_user_ids, allowed_role_ids):
        return True

    monkeypatch.setitem(sys.modules, "plugins.platforms.discord.adapter_component_auth", None)
    monkeypatch.setattr(plugin.adapter._base, "_component_check_auth", sentinel, raising=False)
    assert plugin.adapter._resolve_component_check_auth() is sentinel
