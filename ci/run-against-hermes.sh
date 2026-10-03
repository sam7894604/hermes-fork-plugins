#!/usr/bin/env bash
# Run this repo's tests against a Hermes checkout (upstream by default).
#
#   ci/run-against-hermes.sh                      # clones NousResearch/hermes-agent main into .hermes-upstream/
#   ci/run-against-hermes.sh /path/to/hermes      # use an existing checkout (e.g. /usr/local/lib/hermes-agent)
#   HERMES_REF=v1.2.3 ci/run-against-hermes.sh    # test against a release tag
#
# The plugins are copied to <hermes>/fork-plugins/ and the tests to <hermes>/tests/fork_plugins/ — the
# layout the tests expect (tests/fork_plugins/_plugin_loader.py resolves ../../fork-plugins). The test
# environment is Hermes' own (setup-hermes.sh --test-environment + scripts/run_tests.sh), so results
# match what the Hermes CI would see.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HERMES="${1:-$HERE/.hermes-upstream}"
REF="${HERMES_REF:-main}"
if [ ! -d "$HERMES/.git" ]; then
  git clone --depth 1 --branch "$REF" https://github.com/NousResearch/hermes-agent.git "$HERMES"
fi
echo "hermes: $HERMES @ $(git -C "$HERMES" rev-parse --short HEAD)"
rm -rf "$HERMES/fork-plugins" "$HERMES/tests/fork_plugins"
mkdir -p "$HERMES/fork-plugins" "$HERMES/tests/fork_plugins"
for entry in "$HERE"/*/ "$HERE"/platforms; do
  name="$(basename "$entry")"
  case "$name" in tests|ci|.git|.github|.hermes-upstream) continue;; esac
  cp -r "$entry" "$HERMES/fork-plugins/$name"
done
cp "$HERE/install.sh" "$HERE/README.md" "$HERMES/fork-plugins/"
cp -r "$HERE/tests/." "$HERMES/tests/fork_plugins/"
cd "$HERMES"
export HERMES_HOME="${HERMES_HOME:-$HERMES/.hermes-test-home}"
unset HERMES_PYTHON PYTHONHOME PYTHONPATH VIRTUAL_ENV
if [ ! -x "$(command -v uv || true)" ] && [ ! -x "$HOME/.local/bin/uv" ]; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi
export PATH="$HOME/.local/bin:$PATH"
bash setup-hermes.sh --runtime-only --test-environment
HERMES_TEST_WORKERS="${HERMES_TEST_WORKERS:-4}" scripts/run_tests.sh tests/fork_plugins/ "${@:2}"
