#!/bin/bash

set -uo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
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

check "the declared list matches the gates that exist" t_the_declared_list_matches_the_gates_that_exist
check "an unknown gate is refused" t_an_unknown_gate_is_refused
check "every gate the pipeline names exists" t_every_gate_the_pipeline_names_exists
check "every gate is run by the pipeline" t_every_gate_is_run_by_the_pipeline

printf '\n%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
