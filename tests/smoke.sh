#!/usr/bin/env bash
# Smoke tests for a sandbox created from the OpenCode v2 kit.
#
# Runs on the host and executes its checks inside the sandbox:
#
#   tests/smoke.sh <sandbox> [expected-version]
#
# With SMOKE_RUNNER=docker, <sandbox> is a container started from the kit
# image instead (e.g. `docker run -d --name oc2 --entrypoint sleep
# opencode2-kit:2.1.2 infinity`); the checks that only a sandbox runtime
# can satisfy (agent context, MCP gateway seed) are skipped.
#
# SMOKE_PROMPT=1 also sends one headless prompt (`opencode run`), which
# spends tokens. Set SMOKE_MODEL (provider/model, e.g.
# anthropic/claude-haiku-4-5) to aim it at a provider whose credential is
# bound to the sandbox; otherwise opencode picks its default model, which
# may be a free model served through opencode.ai.
set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "usage: $0 <sandbox> [expected-version]" >&2
  exit 2
fi
target=$1
expected=${2:-}
runner=${SMOKE_RUNNER:-sbx}

case "$runner" in
  sbx) exec_in=(sbx exec "$target" --) ;;
  docker) exec_in=(docker exec "$target") ;;
  *) echo "SMOKE_RUNNER must be sbx or docker, not '$runner'" >&2; exit 2 ;;
esac

# The checks run as one script inside the target, so a single exec carries
# them all and every result line comes back in order.
read -r -d '' checks <<'EOF' || true
expected=$1 runner=$2 prompt=$3 model=$4
failures=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failures=$((failures + 1)); }
skip() { echo "SKIP  $1"; }

# Version: the kit pins one release per build; without an expected value,
# only the major version is checked.
version=$(opencode --version 2>/dev/null || true)
if [ -n "$expected" ]; then
  [ "$version" = "opencode v$expected" ] && pass "version is $expected" || fail "version is '$version', expected $expected"
else
  case "$version" in
    "opencode v2."*) pass "version is v2 ($version)" ;;
    *) fail "version is '$version', expected 2.x" ;;
  esac
fi

[ "$(id -un)" = agent ] && pass "runs as agent" || fail "runs as $(id -un), expected agent"

[ "${OPENCODE_DISABLE_AUTOUPDATE:-}" = 1 ] && pass "auto-update disabled" || fail "OPENCODE_DISABLE_AUTOUPDATE is '${OPENCODE_DISABLE_AUTOUPDATE:-}', expected 1"

# A manual `opencode upgrade --method npm` needs the npm global prefix to
# stay writable by the agent user.
prefix=$(npm prefix -g 2>/dev/null || true)
[ -n "$prefix" ] && [ -w "$prefix/lib/node_modules/@opencode/cli" ] && pass "install is agent-writable ($prefix)" || fail "npm global install is not writable by agent"

config_dir=$(opencode debug paths 2>/dev/null | awk '$1 == "config" { print $2 }')
[ "$config_dir" = /home/agent/.config/opencode ] && pass "config dir is $config_dir" || fail "config dir is '$config_dir'"

if [ "$runner" = sbx ]; then
  [ -s /home/agent/.config/opencode/AGENTS.md ] && pass "agent context present" || fail "agent context missing at ~/.config/opencode/AGENTS.md"
  if [ -n "${MCP_GATEWAY_URL:-}" ]; then
    jq -e '.mcp.servers["mcp-gateway"].url' /home/agent/.config/opencode/opencode.json >/dev/null 2>&1 \
      && pass "MCP gateway registered" || fail "MCP gateway missing from opencode.json"
  else
    skip "MCP gateway (MCP not enabled for this sandbox)"
  fi
else
  skip "agent context and MCP gateway (sandbox runtime only)"
fi

# Providers opencode detects from the proxy-managed key variables; the
# bundled opencode provider is always listed and not counted.
providers=$(timeout 60 opencode models --standalone 2>/dev/null | cut -d/ -f1 | sort -u | grep -vx opencode | tr '\n' ' ')
if [ -n "$providers" ]; then
  pass "providers detected: $providers"
else
  skip "no provider credential bound (only the free opencode models)"
fi

if [ "$prompt" = 1 ]; then
  set -- run
  [ -n "$model" ] && set -- "$@" -m "$model"
  label="headless prompt${model:+ ($model)}"
  if out=$(cd /home/agent/workspace 2>/dev/null; timeout 180 opencode "$@" "Reply with the single word OK." 2>&1); then
    status=pass
  else
    status=fail
  fi
  last=$(printf '%s' "$out" | sed 's/\x1b\[[0-9;]*m//g' | tail -n 1 | cut -c1-120)
  if [ "$status" = pass ]; then pass "$label answered: $last"; else fail "$label failed: $last"; fi
else
  skip "headless prompt (set SMOKE_PROMPT=1)"
fi

echo "---"
if [ "$failures" -eq 0 ]; then echo "all checks passed"; else echo "$failures check(s) failed"; fi
exit "$failures"
EOF

"${exec_in[@]}" bash -c "$checks" smoke "$expected" "$runner" "${SMOKE_PROMPT:-0}" "${SMOKE_MODEL:-}"
