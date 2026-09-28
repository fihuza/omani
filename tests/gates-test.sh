#!/bin/bash

set -uo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
GATES="$ROOT/scripts/pre-commit"
WORKFLOW="$ROOT/.github/workflows/ci.yml"

passed=0
failed=0
current=""

pass() {
  printf 'ok - %s\n' "$1"
  ((passed++))
}

fail() {
  local description="$1" detail="${2:-}"
  [[ -n $detail ]] && printf '  %s\n' "$detail" >&2
  printf 'not ok - %s\n' "$description" >&2
  ((failed++))
}

check() {
  current="$1"
  shift
  local before=$failed
  "$@"
  local status=$?
  ((failed != before)) && return
  ((status == 0)) || fail "$current" "the test itself exited $status"
  ((failed == before)) && pass "$current"
}

gate_names() {
  grep -oE '^if wanted [a-z-]+' "$GATES" | awk '{print $3}' | sort -u
}

t_an_unknown_gate_is_refused() {
  local out
  if out=$("$GATES" not-a-real-gate 2>&1); then
    fail "$current" "expected a non-zero exit, got: $out"
  fi
}

t_every_gate_the_pipeline_names_exists() {
  local named known missing=""
  known=$(gate_names)
  named=$(grep -oE '\./scripts/pre-commit [a-z-]+' "$WORKFLOW" | awk '{print $2}' | sort -u)
  local gate
  for gate in $named; do
    [[ $gate == all ]] && continue
    grep -qx "$gate" <<<"$known" || missing+="$gate "
  done
  [[ -z $missing ]] || fail "$current" "the pipeline runs gates that do not exist: $missing"
}

t_every_gate_is_run_by_the_pipeline() {
  local known named unrun=""
  known=$(gate_names)
  named=$(grep -oE '\./scripts/pre-commit [a-z-]+' "$WORKFLOW" | awk '{print $2}' | sort -u)
  local gate
  for gate in $known; do
    grep -qx "$gate" <<<"$named" || unrun+="$gate "
  done
  [[ -z $unrun ]] || fail "$current" "gates nothing in the pipeline runs: $unrun"
}

t_the_declared_list_matches_the_gates_that_exist() {
  local declared known
  declared=$(sed -nE 's/^GATES=\((.*)\)$/\1/p' "$GATES" | tr ' ' '\n' | sort -u)
  known=$(gate_names)
  [[ $declared == "$known" ]] ||
    fail "$current" "declared [$(tr '\n' ' ' <<<"$declared")] but the script runs [$(tr '\n' ' ' <<<"$known")]"
}

t_every_shape_of_javascript_is_linted() {
  local probe="$WORK/eslint"
  rm -rf "$probe"
  mkdir -p "$probe"
  cp "$ROOT/eslint.config.js" "$ROOT/mise.toml" "$probe/"
  local ext
  for ext in js cjs mjs; do
    printf 'var a = 1\nif (b == 2) { debugger }\n' >"$probe/probe.$ext"
  done

  local out
  out=$(cd "$probe" && eslint . 2>&1)
  local code=$?
  ((code != 0)) || fail "$current" "a planted problem passed: $out"
  for ext in js cjs mjs; do
    grep -q "probe\.$ext" <<<"$out" || fail "$current" ".$ext went unchecked"
  done
}

t_the_config_covers_what_eslint_recommends() {
  local recommended=()
  mapfile -t recommended < <(eslint_recommended)
  ((${#recommended[@]} > 0)) || fail "$current" "could not read what eslint recommends"

  local out
  out=$(cd "$ROOT" && node -e '
    const cfg = require("./eslint.config.js")
    const named = new Set()
    for (const block of cfg) for (const k of Object.keys(block.rules || {})) named.add(k)
    const missing = process.argv.slice(1).filter(function (rule) { return !named.has(rule) })
    if (missing.length) console.log(missing.join(" "))
  ' "${recommended[@]}" 2>&1)
  [[ -z $out ]] || fail "$current" "rules eslint recommends that the config does not name: $out"
}

eslint_package() {
  local bin dir found
  bin=$(command -v eslint) || return 1
  [[ $(readlink -f "$bin") == *"/mise" ]] && bin=$(mise which eslint 2>/dev/null)
  [[ -n $bin ]] || return 1
  dir=$(dirname "$(readlink -f "$bin")")
  local climbed=0
  while ((climbed < 6)); do
    climbed=$((climbed + 1))
    found=$(find "$dir" -maxdepth 8 -type f -path "*/eslint/lib/rules/index.js" 2>/dev/null | head -1)
    [[ -n $found ]] && printf '%s\n' "${found%/lib/rules/index.js}" && return 0
    [[ $dir == / ]] && return 1
    dir=$(dirname "$dir")
  done
  return 1
}

eslint_recommended() {
  local pkg
  pkg=$(eslint_package) || return 0
  [[ -n $pkg ]] || return 0
  node -e '
    const rules = require(process.argv[1] + "/lib/rules/index.js")
    for (const [name, rule] of rules) {
      if (rule && rule.meta && rule.meta.docs && rule.meta.docs.recommended) console.log(name)
    }
  ' "$pkg" 2>/dev/null
}

check "every shape of javascript is linted" t_every_shape_of_javascript_is_linted
check "the config covers what eslint recommends" t_the_config_covers_what_eslint_recommends
check "the declared list matches the gates that exist" t_the_declared_list_matches_the_gates_that_exist
check "an unknown gate is refused" t_an_unknown_gate_is_refused
check "every gate the pipeline names exists" t_every_gate_the_pipeline_names_exists
check "every gate is run by the pipeline" t_every_gate_is_run_by_the_pipeline

printf '\n%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
