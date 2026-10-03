# hermes-fork-plugins

Plugins for [Hermes Agent](https://github.com/NousResearch/hermes-agent) maintained outside the core
tree. They are ordinary **user plugins** (`$HERMES_HOME/plugins/`), written against upstream's plugin
system only, so a Hermes install can follow upstream releases directly and keep these on top.

| Plugin | Kind | What it does |
|---|---|---|
| `platforms/line` | platform override | subclass of the bundled LINE adapter: config-backed whitelist with admin notification and pending queue, `requires_mention` gating (quote-reply of the bot counts), passive group context + on-demand media backfill, display names, Markdown tables → bullets, and the `line_whitelist` agent tool |
| `platforms/discord` | platform override | subclass of the bundled Discord adapter: `? `/`?? ` auto-choice buttons after a reply, and the Approve/Ignore/Skip LINE whitelist card |
| `platforms/telegram` | platform override | subclass of the bundled Telegram adapter: the Approve/Ignore/Skip LINE whitelist card (`linewl:` callbacks) |
| `line-whitelist` | dashboard | LINE allowlist admin tab (users/groups/rooms, pending queue, records, name resolution); reads the store shipped by `platforms/line` |
| `groq-cf-stt` | transcription provider (`stt.provider: groq-cf`) | Groq Whisper through a Cloudflare AI Gateway (`cf-aig-authorization` from `CF_AIG_TOKEN`, BYOK); direct `api.groq.com` behaves like the built-in `groq` backend |
| `tokens-footer` | hooks (`post_api_request` + `transform_llm_output`) | appends the turn's `in/out/rsn/cache` token counts to gateway replies when `tokens` is listed in `display.runtime_footer.fields` |
| `turbovault-fixups` | hooks | repairs malformed `edit_note` SEARCH/REPLACE payloads; skips the doomed local `patch` after a vault write so the file-mutation verifier does not false-alarm |
| `document-extract` | hook (`pre_llm_call`) | inlines the text of attached PDFs/docs/text files that the gateway only saved to disk |
| `cost-estimate` | dashboard | per-model cost over 1h/24h/7d/30d priced per tier, with a daily/monthly projection |

## Install on a host

```bash
git clone https://github.com/sam7894604/hermes-fork-plugins "${HERMES_HOME:-$HOME/.hermes}/fork-plugins"
bash "${HERMES_HOME:-$HOME/.hermes}/fork-plugins/install.sh"   # symlinks every entry into $HERMES_HOME/plugins (idempotent)
hermes plugins enable turbovault-fixups document-extract cost-estimate line-whitelist groq-cf-stt tokens-footer platforms/line platforms/discord platforms/telegram
hermes plugins list       # every entry must show as loaded
hermes gateway restart
```

Update: `git -C "$HERMES_HOME/fork-plugins" pull` then `hermes gateway restart`. The clone lives beside, not
inside, the Hermes checkout, so `hermes update` never touches it.

The six flat plugins can alternatively be installed one by one with upstream's installer
(`hermes plugins install https://github.com/sam7894604/hermes-fork-plugins/tree/main/<plugin>`); the three
`platforms/*` overrides cannot, because they must sit at `$HERMES_HOME/plugins/platforms/<name>/` — the key
that shadows the bundled platform — and the installer only places flat directories.

### Configuration the plugins expect

- `platforms/line`: the LINE env vars of the bundled plugin plus the optional
  `LINE_OBSERVE_UNMENTIONED`, `LINE_MEDIA_BACKFILL_WINDOW_MIN`, `LINE_MEDIA_BACKFILL_CACHE_MAX`,
  `LINE_NAME_CACHE_TTL` (see its `plugin.yaml`); the whitelist itself lives in `config.yaml` under
  `platforms.line.whitelist` and is edited through the dashboard tab or the `line_whitelist` tool.
- `line_whitelist` is a **plugin toolset**, and upstream turns a plugin toolset ON by default on every platform
  that has not recorded it in `known_plugin_toolsets.<platform>`. To keep it LINE-only, add `line_whitelist` to
  `known_plugin_toolsets.<platform>` for every other platform (or save that platform once in `hermes tools`),
  and keep it listed in `platform_toolsets.line`. Where it leaks in, every call is still admin-gated.
- `groq-cf-stt`: `stt.provider: groq-cf`, options under `stt.groq-cf` (`model`, `language`, `prompt`,
  `timeout`, `max_retries`); reads `GROQ_BASE_URL` / `GROQ_API_KEY` / `CF_AIG_TOKEN`.
- `tokens-footer`: `display.runtime_footer: {enabled: true, fields: [model, context_pct, tokens]}` (or the
  per-platform `display.platforms.<p>.runtime_footer` override). Gateway-only.
- `platforms/discord`: `discord.auto_choice_buttons: false` or `DISCORD_AUTO_CHOICE_BUTTONS=false` disables
  the buttons; see `platforms/discord/README.md` for the `? ` / `?? ` reply format.

## How the platform overrides work, and what they cost

Each override imports the bundled adapter module (`plugins.platforms.<name>.adapter`), subclasses its
adapter class, and re-runs upstream's own `register()` through a delegating context that swaps only
`adapter_factory`. The platform entry (label, env names, install hint, limits, platform hint) is therefore
always upstream's; `tests/test_platform_overrides_registration.py` asserts that relationship against the
live upstream module.

**Fallback.** Each override's `__init__.py` wraps `register()`: if `adapter.py` fails to import against the
installed Hermes (an upstream seam moved) or its registration raises, upstream's stock adapter for that
platform is registered instead and an ERROR is logged naming what is off. The platform stays up without
the extras (LINE: the static `LINE_ALLOWED_*` env allowlists decide; empty lists deny everyone).

Unlike bundled platforms, which upstream registers *deferred*, a user platform plugin is loaded eagerly
whenever plugins are discovered — including CLI start. Measured on a production host (PM Python 3.14,
SDKs installed, cold): plugin discovery alone ~185 ms, discovery plus the three adapters ~640 ms, so the
overrides add about 0.45 s to a `hermes` start that runs plugin discovery; the gateway imports them anyway.

Other deliberate behaviour notes:

- Delegated subagents **see** `line_whitelist` in their schema when the parent has it (the static
  `DELEGATE_BLOCKED_TOOLS` list cannot name a plugin tool) but every call from a delegated child is refused by
  the handler (`agent.delegation_context.is_delegated_child_process_context`).
- `groq-cf-stt` is a *new* provider name because a plugin may not override the built-in `groq` backend.
- Discord auto-choice buttons are sent after `send()` returns success, never into a forum parent channel.
- The Discord/Telegram cards and the `line-whitelist` dashboard reach `WhitelistStore` through the LINE
  plugin's module when it is loaded in the same process, else by importing
  `$HERMES_HOME/plugins/platforms/line/whitelist_store.py` by path — so the dashboard process works without
  loading platform plugins, and Discord/Telegram degrade to "Whitelist unavailable" when the LINE override
  is not installed.

## Tests

`tests/` are pytest files written for Hermes' own runner; they expect to live at
`<hermes>/tests/fork_plugins/` with the plugins at `<hermes>/fork-plugins/`. `ci/run-against-hermes.sh`
places them there and runs `scripts/run_tests.sh tests/fork_plugins/` inside Hermes' canonical test
environment:

```bash
ci/run-against-hermes.sh                       # clones upstream main into .hermes-upstream/ and tests against it
ci/run-against-hermes.sh /usr/local/lib/hermes-agent   # against an existing checkout
HERMES_REF=v1.2.3 ci/run-against-hermes.sh     # against a release tag
```

The GitHub Actions workflow runs the same script on every push and daily against upstream `main`, so a
seam change upstream shows up as a red run before it reaches a host that follows upstream.
