#!/bin/bash

set -uo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
OMANI="$ROOT/bin/omani"

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

# A stopped player lingers as a zombie until its parent reaps it, and nothing
# here is that parent -- under a CI container whose pid 1 never calls wait(),
# the zombie is permanent and `kill -0` still answers yes. Process state is what
# says whether a player is really gone.
still_running() {
  local state
  state=$(sed -n 's/^State:[[:space:]]*\([A-Z]\).*/\1/p' "/proc/$1/status" 2>/dev/null)
  [[ -n $state && $state != "Z" ]]
}

wait_until_gone() {
  local i
  for ((i = 0; i < 50; i++)); do
    still_running "$1" || return 0
    sleep 0.1
  done
  return 1
}

started_at() {
  local stat
  stat=$(</proc/"$1"/stat) 2>/dev/null || return 1
  stat=${stat#*) }
  awk '{print $20}' <<<"$stat"
}

live_player() {
  sleep 60 >/dev/null 2>&1 &
  local pid=$!
  printf '%s\n' "$pid" >>"$WORK/spawned"
  mkdir -p "$OMANI_STATE_DIR"
  printf '%s\t%s\t%s\t%s\t\t%s\n' "$pid" "$1" "$2" "$3" "$(started_at "$pid")" >>"$OMANI_STATE_DIR/players"
  printf '%s\n' "$pid"
}

seed_history() {
  printf '{"version":1,"series":%s}\n' "$1" >"$OMANI_HIST_FILE"
}

series_field() {
  "$OMANI" history | jq -r --arg id "$1" ".series[\$id] | $2"
}

setup() {
  WORK=$(mktemp -d)
  export OMANI_HIST_FILE="$WORK/history.json"
  export OMANI_STATE_DIR="$WORK/state"
  export OMANI_PLAYER=mpv
  mkdir -p "$WORK/mpv-scripts"
  : >"$WORK/mpv-scripts/mpris.so"
  export OMANI_MPV_SCRIPT_DIRS="$WORK/mpv-scripts"
  export OMANI_MPV_CONF_FILES="$WORK/absent.conf"
  export OMANI_DRY_RUN=1
  unset OMANI_QUALITY OMANI_MODE

  cat >"$WORK/provider" <<'FAKE'
#!/bin/bash
case "$1" in
search) printf 'frieren-1\tFrieren\nnaruto-2\tNaruto\n' ;;
episodes) printf '9001\t1\n9002\t2\n9003\t3\n' ;;
stream)
  printf 'url\thttps://cdn/%s/%s.m3u8\nreferrer\thttps://embed/\nsubtitles\thttps://cdn/subs.vtt\n' "$2" "$3"
  ;;
esac
FAKE
  chmod +x "$WORK/provider"
  export OMANI_PROVIDER="$WORK/provider"

  cat >"$WORK/player" <<'FAKEPLAYER'
#!/bin/bash
exec sleep 60
FAKEPLAYER
  chmod +x "$WORK/player"

  seed_history '{"frieren-1": {"title": "Frieren", "episode": "2", "episodes": {}},
                 "naruto-2":  {"title": "Naruto",  "episode": "5", "episodes": {}}}'
}

teardown() {
  if [[ -f $WORK/spawned ]]; then
    local pid
    while read -r pid; do kill "$pid" 2>/dev/null; done <"$WORK/spawned"
    while read -r pid; do still_running "$pid" && kill -9 "$pid" 2>/dev/null; done <"$WORK/spawned"
  fi
  rm -rf "$WORK"
}

assert_ok() { (($1 == 0)) || fail "$current" "expected success, got exit $1"; }
assert_fails() { (($1 != 0)) || fail "$current" "expected failure, got exit 0"; }
assert_eq() { [[ $1 == "$2" ]] || fail "$current" "expected '$2', got '$1'"; }
assert_contains() { [[ $1 == *"$2"* ]] || fail "$current" "expected '$2' in: $1"; }
assert_lacks() { [[ $1 != *"$2"* ]] || fail "$current" "did not expect '$2' in: $1"; }
assert_file() { [[ -f $1 ]] || fail "$current" "expected file: $1"; }

check() {
  current="$1"
  shift
  setup
  local before=$failed
  "$@"
  local status=$?
  if ((failed == before)); then
    ((status == 0)) || fail "$current" "the test itself exited $status"
    ((failed == before)) && pass "$current"
  fi
  teardown
}

t_status_json() {
  local out
  out=$("$OMANI" status)
  assert_ok $?
  jq -e . <<<"$out" >/dev/null || fail "$current" "not json: $out"
}

t_status_reports_the_history_path() {
  assert_eq "$("$OMANI" status | jq -r .historyPath)" "$OMANI_HIST_FILE"
}

t_status_reports_the_repository() {
  assert_eq "$("$OMANI" status | jq -r .repo)" "https://github.com/fihuza/omani"
}

t_status_reports_the_plugin_version() {
  printf '{"version":"9.9.9"}\n' >"$WORK/manifest.json"
  assert_eq "$(OMANI_MANIFEST="$WORK/manifest.json" "$OMANI" status | jq -r .version)" "9.9.9"
}

t_status_survives_a_missing_manifest() {
  local out
  out=$(OMANI_MANIFEST="$WORK/absent.json" "$OMANI" status)
  assert_ok $?
  assert_eq "$(jq -r .version <<<"$out")" ""
}

t_status_uses_the_real_script_dirs_by_default() {
  local out
  out=$(env -u OMANI_MPV_SCRIPT_DIRS "$OMANI" status)
  assert_ok $?
  assert_contains "$(jq -r 'has("tracking") | tostring' <<<"$out")" "true"
}

t_status_finds_mpris_loaded_by_path_in_the_config() {
  printf 'script=/usr/lib/mpv-mpris/mpris.so\n' >"$WORK/mpv.conf"
  local out
  out=$(OMANI_MPV_SCRIPT_DIRS="$WORK/nowhere" OMANI_MPV_CONF_FILES="$WORK/mpv.conf" "$OMANI" status)
  assert_eq "$(jq -r .tracking <<<"$out")" "true"
}

t_status_ignores_an_unrelated_script_line() {
  printf 'script=/usr/lib/mpv/other.so\nvolume=80\n' >"$WORK/mpv.conf"
  local out
  out=$(OMANI_MPV_SCRIPT_DIRS="$WORK/nowhere" OMANI_MPV_CONF_FILES="$WORK/mpv.conf" "$OMANI" status)
  assert_eq "$(jq -r .tracking <<<"$out")" "false"
}

t_status_names_mpv_mpris_when_absent() {
  local out
  out=$(OMANI_MPV_SCRIPT_DIRS="$WORK/nowhere" "$OMANI" status)
  assert_eq "$(jq -r .tracking <<<"$out")" "false"
  assert_lacks "$(jq -r .missing <<<"$out")" "mpv-mpris"
}

t_status_accepts_mpris_from_any_script_dir() {
  mkdir -p "$WORK/second"
  : >"$WORK/second/mpris.so"
  local out
  out=$(OMANI_MPV_SCRIPT_DIRS="$WORK/nowhere:$WORK/second" "$OMANI" status)
  assert_eq "$(jq -r .tracking <<<"$out")" "true"
}

t_status_names_a_missing_player() {
  local out
  out=$(OMANI_PLAYER="definitely-absent-$$" "$OMANI" status)
  assert_eq "$(jq -r .ready <<<"$out")" "false"
  assert_contains "$(jq -r .missing <<<"$out")" "definitely-absent"
}

t_search_returns_provider_rows() {
  assert_contains "$("$OMANI" search frieren)" "frieren-1	Frieren"
}

t_episodes_returns_provider_rows() {
  assert_contains "$("$OMANI" episodes frieren-1)" "9002	2"
}

t_play_builds_a_player_command() {
  local out
  out=$("$OMANI" play frieren-1 "Frieren" 3)
  assert_ok $?
  assert_contains "$out" "mpv"
  assert_contains "$out" "--force-media-title=Frieren Episode 3"
  assert_contains "$out" "--referrer=https://embed/"
  assert_contains "$out" "https://cdn/frieren-1/3.m3u8"
}

t_play_asks_the_provider_for_the_requested_quality() {
  cat >"$WORK/provider" <<'FAKE'
#!/bin/bash
[[ $1 == stream ]] && printf 'url\thttps://cdn/%s.m3u8\nreferrer\thttps://e/\nsubtitles\t\n' "$5"
FAKE
  chmod +x "$WORK/provider"
  assert_contains "$(OMANI_QUALITY=720 "$OMANI" play frieren-1 "Frieren" 1)" "https://cdn/720.m3u8"
}

t_play_without_a_quality_asks_for_the_default() {
  cat >"$WORK/provider" <<'FAKE'
#!/bin/bash
[[ $1 == stream ]] && printf 'url\thttps://cdn/%s.m3u8\nreferrer\thttps://e/\nsubtitles\t\n' "${5:-unset}"
FAKE
  chmod +x "$WORK/provider"
  assert_contains "$("$OMANI" play frieren-1 "Frieren" 1)" "https://cdn/best.m3u8"
}

t_play_passes_subtitles_when_offered() {
  assert_contains "$("$OMANI" play frieren-1 "Frieren" 1)" "--sub-file=https://cdn/subs.vtt"
}

t_play_omits_subtitles_when_absent() {
  cat >"$WORK/provider" <<'FAKE'
#!/bin/bash
[[ $1 == stream ]] && printf 'url\thttps://cdn/x.m3u8\nreferrer\thttps://e/\nsubtitles\t\n'
FAKE
  chmod +x "$WORK/provider"
  assert_lacks "$("$OMANI" play frieren-1 "Frieren" 1)" "--sub-file"
}

t_play_needs_all_three_arguments() {
  "$OMANI" play frieren-1 "Frieren" >/dev/null 2>&1
  assert_fails $?
}

t_play_drops_a_subtitle_that_is_not_a_web_address() {
  cat >"$WORK/provider" <<'FAKE'
#!/bin/bash
case "$1" in
episodes) printf '9001\t1\n' ;;
stream) printf 'url\thttps://cdn/a.m3u8\nreferrer\thttps://e/\nsubtitles\t%s\n' "${FAKE_SUBS:-}" ;;
esac
FAKE
  chmod +x "$WORK/provider"
  local subs out
  for subs in file:///etc/passwd /etc/shadow --sub-file=/etc/shadow; do
    out=$(FAKE_SUBS="$subs" "$OMANI" play frieren-1 "Frieren" 1 2>&1)
    assert_ok $?
    assert_lacks "$out" "--sub-file"
    assert_lacks "$out" "etc"
  done
}

t_play_keeps_a_subtitle_that_is_a_web_address() {
  cat >"$WORK/provider" <<'FAKE'
#!/bin/bash
case "$1" in
episodes) printf '9001\t1\n' ;;
stream) printf 'url\thttps://cdn/a.m3u8\nreferrer\thttps://e/\nsubtitles\thttps://cdn/en.vtt\n' ;;
esac
FAKE
  chmod +x "$WORK/provider"
  assert_contains "$("$OMANI" play frieren-1 "Frieren" 1)" "--sub-file=https://cdn/en.vtt"
}

t_play_refuses_a_url_the_provider_should_not_have_sent() {
  cat >"$WORK/provider" <<'FAKE'
#!/bin/bash
case "$1" in
episodes) printf '9001\t1\n' ;;
stream) printf 'url\t%s\nreferrer\thttps://e/\n' "${FAKE_URL:--v}" ;;
esac
FAKE
  chmod +x "$WORK/provider"
  local url out
  for url in -v --version file:///etc/passwd /etc/shadow; do
    out=$(FAKE_URL="$url" "$OMANI" play frieren-1 "Frieren" 1 2>&1)
    assert_fails $?
    assert_contains "$out" "not a playable"
  done
}

t_the_player_is_told_where_its_arguments_end() {
  assert_contains "$("$OMANI" play frieren-1 "Frieren" 3)" " -- http"
}

t_play_fails_when_no_source_resolves() {
  cat >"$WORK/provider" <<'FAKE'
#!/bin/bash
[[ $1 == stream ]] && printf 'url\t\nreferrer\t\nsubtitles\t\n'
FAKE
  chmod +x "$WORK/provider"
  local out
  out=$("$OMANI" play frieren-1 "Frieren" 9 2>&1)
  assert_fails $?
  assert_contains "$out" "no playable source"
}

t_play_records_a_new_series() {
  OMANI_DRY_RUN='' OMANI_PLAYER=true "$OMANI" play new-9 "Newcomer" 1
  assert_eq "$(series_field new-9 .episode)" "1"
  assert_eq "$(series_field new-9 .title)" "Newcomer"
}

t_play_advances_a_series_already_watched() {
  OMANI_DRY_RUN='' OMANI_PLAYER=true "$OMANI" play frieren-1 "Frieren" 7
  assert_eq "$(series_field frieren-1 .episode)" "7"
  assert_eq "$("$OMANI" history | jq -r '.series | length')" "2"
}

t_history_timestamps_are_finer_than_a_second() {
  OMANI_DRY_RUN='' OMANI_PLAYER=true "$OMANI" play frieren-1 "Frieren" 1
  local updated
  updated=$(series_field frieren-1 .updated)
  ((updated > 1000000000000)) || fail "$current" "updated $updated is in seconds"
}

t_a_record_carries_when_its_player_started() {
  OMANI_DRY_RUN='' OMANI_PLAYER="$WORK/player" "$OMANI" play frieren-1 "Frieren" 3
  cut -f1 "$OMANI_STATE_DIR/players" >>"$WORK/spawned"
  local started
  started=$(awk -F'\t' '$3 == "frieren-1" { print $6 }' "$OMANI_STATE_DIR/players")
  [[ $started =~ ^[0-9]+$ ]] || fail "$current" "start time is '$started'"
}

t_a_player_that_exits_at_once_leaves_a_record_and_no_noise() {
  local noise
  noise=$(OMANI_DRY_RUN='' OMANI_PLAYER=true "$OMANI" play frieren-1 "Frieren" 4 2>&1 >/dev/null)
  assert_eq "$noise" ""
  assert_contains "$(cat "$OMANI_STATE_DIR/players")" "Frieren Episode 4"
}

t_a_player_pid_taken_over_by_something_else_is_not_listed() {
  local pid
  pid=$(live_player "Frieren Episode 3" frieren-1 3)
  printf '%s\tImpostor Episode 1\timpostor-1\t1\t\t1\n' "$$" >>"$OMANI_STATE_DIR/players"
  local out
  out=$("$OMANI" players)
  assert_contains "$out" "Frieren Episode 3"
  assert_lacks "$out" "Impostor"
  printf '%s\n' "$pid" >>"$WORK/spawned"
}

t_play_leaves_other_series_alone() {
  OMANI_DRY_RUN='' OMANI_PLAYER=true "$OMANI" play frieren-1 "Frieren" 7
  assert_eq "$(series_field naruto-2 .episode)" "5"
}

t_history_survives_a_title_with_punctuation() {
  OMANI_DRY_RUN='' OMANI_PLAYER=true "$OMANI" play tricky-3 'A|B&C\D' 4
  assert_eq "$(series_field tricky-3 .title)" 'A|B&C\D'
}

t_progress_records_how_far_in_you_are() {
  OMANI_DRY_RUN='' "$OMANI" progress frieren-1 2 600 1400
  assert_eq "$(series_field frieren-1 '.episodes["2"].position')" "600"
  assert_eq "$(series_field frieren-1 '.episodes["2"].duration')" "1400"
}

t_finishing_an_episode_moves_the_series_on() {
  OMANI_DRY_RUN='' "$OMANI" progress frieren-1 2 1390 1400
  assert_eq "$(series_field frieren-1 .episode)" "3"
}

t_the_threshold_that_finishes_an_episode_can_be_set() {
  OMANI_WATCHED_FRACTION=50 OMANI_DRY_RUN='' "$OMANI" progress frieren-1 2 700 1400
  assert_eq "$(series_field frieren-1 .episode)" "3"
}

t_a_threshold_that_is_not_a_percentage_falls_back() {
  OMANI_WATCHED_FRACTION=nonsense OMANI_DRY_RUN='' "$OMANI" progress frieren-1 2 700 1400
  assert_eq "$(series_field frieren-1 .episode)" "2"
  assert_eq "$(OMANI_WATCHED_FRACTION=nonsense "$OMANI" status | jq -r .watchedFraction)" "90"
}

t_finishing_looks_up_the_next_episode_once() {
  OMANI_DRY_RUN='' "$OMANI" progress frieren-1 2 1390 1400
  OMANI_DRY_RUN='' "$OMANI" progress frieren-1 2 1395 1400
  assert_eq "$(series_field frieren-1 .episode)" "3"
}

t_part_way_through_leaves_the_series_where_it_is() {
  OMANI_DRY_RUN='' "$OMANI" progress frieren-1 2 600 1400
  assert_eq "$(series_field frieren-1 .episode)" "2"
}

t_progress_keeps_each_episode_apart() {
  OMANI_DRY_RUN='' "$OMANI" progress frieren-1 2 600 1400
  OMANI_DRY_RUN='' "$OMANI" progress frieren-1 3 100 1400
  assert_eq "$(series_field frieren-1 '.episodes["2"].position')" "600"
  assert_eq "$(series_field frieren-1 '.episodes["3"].position')" "100"
}

t_progress_replaces_the_position_of_the_same_episode() {
  OMANI_DRY_RUN='' "$OMANI" progress frieren-1 2 600 1400
  OMANI_DRY_RUN='' "$OMANI" progress frieren-1 2 900 1400
  assert_eq "$(series_field frieren-1 '.episodes | length')" "1"
  assert_eq "$(series_field frieren-1 '.episodes["2"].position')" "900"
}

t_progress_refuses_a_series_not_in_history() {
  local out
  out=$(OMANI_DRY_RUN='' "$OMANI" progress nope-0 1 10 100 2>&1)
  assert_fails $?
  assert_contains "$out" "not in history"
}

t_progress_refuses_a_position_that_is_not_seconds() {
  local out
  out=$(OMANI_DRY_RUN='' "$OMANI" progress frieren-1 2 half 1400 2>&1)
  assert_fails $?
}

t_resume_restarts_the_episode_where_it_stopped() {
  OMANI_DRY_RUN='' "$OMANI" progress frieren-1 2 600 1400
  local out
  out=$("$OMANI" resume frieren-1)
  assert_contains "$out" "--force-media-title=Frieren Episode 2"
  assert_contains "$out" "--start=600"
}

t_resume_moves_on_when_the_episode_was_nearly_finished() {
  OMANI_DRY_RUN='' "$OMANI" progress frieren-1 2 1330 1400
  local out
  out=$("$OMANI" resume frieren-1)
  assert_contains "$out" "--force-media-title=Frieren Episode 3"
  assert_lacks "$out" "--start="
}

t_a_series_with_no_progress_plays_the_episode_it_is_on() {
  local out
  out=$("$OMANI" resume frieren-1)
  assert_contains "$out" "Frieren Episode 2"
  assert_lacks "$out" "--start="
}

t_resume_plays_the_episode_after_one_watched_to_the_end() {
  OMANI_DRY_RUN='' "$OMANI" progress frieren-1 2 1400 1400
  assert_contains "$("$OMANI" resume frieren-1)" "--force-media-title=Frieren Episode 3"
}

t_resume_refuses_an_unknown_series() {
  local out
  out=$("$OMANI" resume nope-0 2>&1)
  assert_fails $?
  assert_contains "$out" "not in history"
}

t_resume_refuses_when_nothing_follows() {
  seed_history '{"frieren-1": {"title": "Frieren", "episode": "3", "episodes": {"3": {"position": 1400, "duration": 1400}}}}'
  local out
  out=$("$OMANI" resume frieren-1 2>&1)
  assert_fails $?
  assert_contains "$out" "no episode after"
}

t_next_plays_the_episode_after_the_one_watched() {
  assert_contains "$("$OMANI" next frieren-1)" "--force-media-title=Frieren Episode 3"
}

t_next_moves_on_from_an_episode_barely_started() {
  OMANI_DRY_RUN='' "$OMANI" progress frieren-1 2 30 1400
  local out
  out=$("$OMANI" next frieren-1)
  assert_contains "$out" "--force-media-title=Frieren Episode 3"
  assert_lacks "$out" "--start="
}

t_next_leaves_the_progress_of_the_episode_it_leaves() {
  OMANI_DRY_RUN='' "$OMANI" progress frieren-1 2 30 1400
  OMANI_DRY_RUN='' "$OMANI" next frieren-1
  assert_eq "$(series_field frieren-1 '.episodes["2"].position')" "30"
  assert_eq "$(series_field frieren-1 .episode)" "3"
}

t_next_steps_from_the_newest_player_of_a_series() {
  seed_history '{"naruto-1": {"title": "Naruto", "episode": "1", "episodes": {}}}'
  mkdir -p "$OMANI_STATE_DIR"
  local older newer
  sleep 60 >/dev/null 2>&1 &
  older=$!
  printf '%s\n' "$older" >>"$WORK/spawned"
  sleep 60 >/dev/null 2>&1 &
  newer=$!
  printf '%s\n' "$newer" >>"$WORK/spawned"
  printf '%s\tNaruto Episode 1\tnaruto-1\t1\t1080\t%s\n' "$older" "$(awk '{print $22}' "/proc/$older/stat")" >>"$OMANI_STATE_DIR/players"
  printf '%s\tNaruto Episode 2\tnaruto-1\t2\t1080\t%s\n' "$newer" "$(awk '{print $22}' "/proc/$newer/stat")" >>"$OMANI_STATE_DIR/players"

  assert_contains "$("$OMANI" next naruto-1 2>&1)" "Episode 3"
}

t_next_steps_from_the_episode_actually_playing() {
  seed_history '{"frieren-1": {"title": "Frieren", "episode": "2", "episodes": {}}}'
  local pid
  pid=$(live_player "Frieren Episode 2" frieren-1 2)
  OMANI_DRY_RUN='' "$OMANI" progress frieren-1 2 1330 1400
  assert_eq "$(series_field frieren-1 .episode)" "3"
  assert_contains "$("$OMANI" next frieren-1)" "Frieren Episode 3"
  assert_contains "$("$OMANI" previous frieren-1)" "Frieren Episode 1"
  printf '%s\n' "$pid" >>"$WORK/spawned"
}

t_a_history_that_carries_trailing_garbage_reads_as_empty() {
  printf '{"version":1,"series":{"a":{"title":"A","episode":"1","episodes":{}}}}\nnot json\n' >"$OMANI_HIST_FILE"
  assert_eq "$("$OMANI" history | jq -s 'length')" "1"
  assert_eq "$("$OMANI" history | jq -r '.series | length')" "0"
}

t_clearing_refuses_when_the_backup_cannot_be_written() {
  seed_history '{"frieren-1": {"title": "Frieren", "episode": "2", "episodes": {}}}'
  # A symlink to a directory that does not exist: cp follows it and fails, which
  # root cannot bypass the way it bypasses permissions.
  ln -s "$WORK/no-such-dir/history.json" "$OMANI_HIST_FILE.bak"
  local out
  out=$(OMANI_DRY_RUN='' "$OMANI" history-clear 2>&1)
  local code=$?
  ((code != 0)) || fail "$current" "cleared the history while keeping no backup"
  assert_contains "$(cat "$OMANI_HIST_FILE")" "Frieren"
}

t_a_player_record_leaves_no_temporary_file_behind() {
  OMANI_DRY_RUN='' "$OMANI" play frieren-1 "Frieren" 4 >/dev/null 2>&1
  OMANI_DRY_RUN='' "$OMANI" stop frieren-1 >/dev/null 2>&1
  local leftovers
  leftovers=$(find "$OMANI_STATE_DIR" -name "players.??????" | wc -l)
  assert_eq "$leftovers" "0"
}

t_a_player_list_that_cannot_be_written_is_said_so() {
  printf 'not a directory\n' >"$WORK/blocked-state"
  local out
  out=$(OMANI_STATE_DIR="$WORK/blocked-state/omani" OMANI_DRY_RUN='' "$OMANI" play frieren-1 "Frieren" 4 2>&1)
  local code=$?
  ((code != 0)) || fail "$current" "reported success while recording nothing"
  assert_contains "$out" "player"
  assert_lacks "$out" "mktemp"
}

t_a_history_that_cannot_be_written_is_said_so() {
  # A file where the directory should be: root ignores permissions, but nobody
  # gets to write inside a regular file.
  printf 'not a directory\n' >"$WORK/blocked"
  local out
  out=$(OMANI_HIST_FILE="$WORK/blocked/history.json" OMANI_DRY_RUN='' "$OMANI" progress frieren-1 2 30 1400 2>&1)
  local code=$?
  ((code != 0)) || fail "$current" "reported success while writing nothing"
  assert_contains "$out" "history"
  assert_lacks "$out" "mktemp"
}

t_a_history_that_does_not_parse_is_never_written_over() {
  printf 'not json at all\n' >"$OMANI_HIST_FILE"
  local out
  out=$(OMANI_DRY_RUN='' OMANI_PLAYER=true "$OMANI" play frieren-1 "Frieren" 3 2>&1)
  assert_fails $?
  assert_contains "$out" "not valid json"
  assert_eq "$(cat "$OMANI_HIST_FILE")" "not json at all"
}

t_next_refuses_at_the_last_episode() {
  seed_history '{"frieren-1": {"title": "Frieren", "episode": "3", "episodes": {}}}'
  local out
  out=$("$OMANI" next frieren-1 2>&1)
  assert_fails $?
  assert_contains "$out" "no episode after"
}

t_next_refuses_an_unknown_series() {
  local out
  out=$("$OMANI" next nope-0 2>&1)
  assert_fails $?
  assert_contains "$out" "not in history"
}

t_forget_drops_one_series() {
  OMANI_DRY_RUN='' "$OMANI" forget frieren-1
  assert_ok $?
  assert_eq "$("$OMANI" history | jq -r '.series | keys | join(",")')" "naruto-2"
}

t_a_report_racing_a_forget_does_not_bring_the_series_back() {
  local i
  for i in $(seq 1 12); do
    OMANI_DRY_RUN='' "$OMANI" progress frieren-1 "$i" $((i * 10)) 1400 &
  done
  OMANI_DRY_RUN='' "$OMANI" forget frieren-1 &
  wait
  assert_eq "$("$OMANI" history | jq -r '.series | has("frieren-1")')" "false"
}

t_forget_refuses_a_series_not_in_history() {
  local out
  out=$("$OMANI" forget nope-0 2>&1)
  assert_fails $?
  assert_contains "$out" "not in history"
}

t_forget_needs_an_id() {
  local out
  out=$("$OMANI" forget 2>&1)
  assert_fails $?
  assert_contains "$out" "usage"
}

t_previous_plays_the_episode_before_the_one_watched() {
  assert_contains "$("$OMANI" previous frieren-1)" "--force-media-title=Frieren Episode 1"
}

t_previous_resumes_an_episode_left_part_way() {
  seed_history '{"frieren-1": {"title": "Frieren", "episode": "2",
                 "episodes": {"1": {"position": 300, "duration": 1400}}}}'
  assert_contains "$("$OMANI" previous frieren-1)" "--start=300"
}

t_previous_restarts_an_episode_already_watched() {
  seed_history '{"frieren-1": {"title": "Frieren", "episode": "2",
                 "episodes": {"1": {"position": 1350, "duration": 1400}}}}'
  local out
  out=$("$OMANI" previous frieren-1)
  assert_contains "$out" "Frieren Episode 1"
  assert_lacks "$out" "--start="
}

t_previous_starts_an_episode_never_opened_at_the_beginning() {
  seed_history '{"frieren-1": {"title": "Frieren", "episode": "2", "episodes": {}}}'
  assert_lacks "$("$OMANI" previous frieren-1)" "--start="
}

t_next_resumes_an_episode_left_part_way() {
  seed_history '{"frieren-1": {"title": "Frieren", "episode": "1",
                 "episodes": {"2": {"position": 420, "duration": 1400}}}}'
  assert_contains "$("$OMANI" next frieren-1)" "--start=420"
}

t_replay_starts_at_the_beginning_however_far_in_you_were() {
  seed_history '{"frieren-1": {"title": "Frieren", "episode": "2",
                 "episodes": {"2": {"position": 600, "duration": 1400}}}}'
  assert_lacks "$("$OMANI" play frieren-1 "Frieren" 2 0)" "--start="
}

t_a_position_that_is_not_a_count_of_seconds_starts_from_the_beginning() {
  seed_history '{"frieren-1": {"title": "Frieren", "episode": "2",
                 "episodes": {"2": {"position": -5, "duration": 1400}}}}'
  local out
  out=$("$OMANI" play frieren-1 "Frieren" 2 2>&1)
  assert_ok $?
  assert_lacks "$out" "--start="
}

t_a_position_past_the_end_counts_as_watched() {
  seed_history '{"frieren-1": {"title": "Frieren", "episode": "2",
                 "episodes": {"2": {"position": 1500, "duration": 1400}}}}'
  assert_lacks "$("$OMANI" play frieren-1 "Frieren" 2)" "--start="
}

t_a_position_with_no_duration_is_still_where_it_was_left() {
  seed_history '{"frieren-1": {"title": "Frieren", "episode": "2",
                 "episodes": {"2": {"position": 240, "duration": 0}}}}'
  assert_contains "$("$OMANI" play frieren-1 "Frieren" 2)" "--start=240"
}

t_an_episodes_field_that_is_not_an_object_starts_from_the_beginning() {
  seed_history '{"frieren-1": {"title": "Frieren", "episode": "2", "episodes": "nonsense"}}'
  local out
  out=$("$OMANI" play frieren-1 "Frieren" 2 2>&1)
  assert_ok $?
  assert_lacks "$out" "--start="
}

t_choosing_an_episode_picks_it_up_where_it_was_left() {
  seed_history '{"frieren-1": {"title": "Frieren", "episode": "2",
                 "episodes": {"2": {"position": 600, "duration": 1400}}}}'
  assert_contains "$("$OMANI" play frieren-1 "Frieren" 2)" "--start=600"
}

t_choosing_an_episode_watched_to_the_end_starts_it_again() {
  seed_history '{"frieren-1": {"title": "Frieren", "episode": "2",
                 "episodes": {"2": {"position": 1350, "duration": 1400}}}}'
  assert_lacks "$("$OMANI" play frieren-1 "Frieren" 2)" "--start="
}

t_previous_refuses_at_the_first_episode() {
  seed_history '{"frieren-1": {"title": "Frieren", "episode": "1", "episodes": {}}}'
  local out
  out=$("$OMANI" previous frieren-1 2>&1)
  assert_fails $?
  assert_contains "$out" "no episode before"
}

t_previous_refuses_an_unknown_series() {
  local out
  out=$("$OMANI" previous nope-0 2>&1)
  assert_fails $?
  assert_contains "$out" "not in history"
}

t_the_recorded_pid_is_the_player_itself() {
  OMANI_DRY_RUN='' OMANI_PLAYER="$WORK/player" "$OMANI" play frieren-1 "Frieren" 3
  local pid
  pid=$(cut -f1 "$OMANI_STATE_DIR/players")
  printf '%s\n' "$pid" >>"$WORK/spawned"
  still_running "$pid" || fail "$current" "recorded pid $pid is not alive"
}

t_stop_closes_the_player() {
  OMANI_DRY_RUN='' OMANI_PLAYER="$WORK/player" "$OMANI" play frieren-1 "Frieren" 3
  local pid
  pid=$(cut -f1 "$OMANI_STATE_DIR/players")
  printf '%s\n' "$pid" >>"$WORK/spawned"
  OMANI_DRY_RUN='' "$OMANI" stop "$pid"
  wait_until_gone "$pid" || fail "$current" "player $pid survived stop"
}

t_resume_closes_the_player_the_series_already_has() {
  OMANI_DRY_RUN='' OMANI_PLAYER="$WORK/player" "$OMANI" play frieren-1 "Frieren" 2
  local first
  first=$(cut -f1 "$OMANI_STATE_DIR/players")
  printf '%s\n' "$first" >>"$WORK/spawned"

  OMANI_DRY_RUN='' OMANI_PLAYER="$WORK/player" "$OMANI" resume frieren-1
  cut -f1 "$OMANI_STATE_DIR/players" >>"$WORK/spawned"

  wait_until_gone "$first" || fail "$current" "the player of the same series is still running"
  assert_eq "$("$OMANI" players | wc -l)" "1"
}

t_one_player_per_series_whoever_asks() {
  OMANI_DRY_RUN='' OMANI_PLAYER="$WORK/player" "$OMANI" play frieren-1 "Frieren" 1
  local first
  first=$(cut -f1 "$OMANI_STATE_DIR/players")
  printf '%s\n' "$first" >>"$WORK/spawned"

  OMANI_DRY_RUN='' OMANI_PLAYER="$WORK/player" "$OMANI" play frieren-1 "Frieren" 2
  cut -f1 "$OMANI_STATE_DIR/players" >>"$WORK/spawned"
  wait_until_gone "$first" || fail "$current" "the first player of the series is still running"
  assert_eq "$("$OMANI" players | wc -l)" "1"
  assert_contains "$("$OMANI" players)" "Frieren Episode 2"
}

t_another_series_adds_a_player_rather_than_replacing_one() {
  OMANI_DRY_RUN='' OMANI_PLAYER="$WORK/player" "$OMANI" play frieren-1 "Frieren" 1
  OMANI_DRY_RUN='' OMANI_PLAYER="$WORK/player" "$OMANI" play naruto-2 "Naruto" 9
  cut -f1 "$OMANI_STATE_DIR/players" >>"$WORK/spawned"
  assert_eq "$("$OMANI" players | wc -l)" "2"
}

t_play_records_the_player_it_started() {
  OMANI_DRY_RUN='' OMANI_PLAYER=true "$OMANI" play frieren-1 "Frieren" 3
  assert_contains "$(cat "$OMANI_STATE_DIR/players")" "Frieren Episode 3	frieren-1	3"
}

t_two_episodes_are_tracked_at_once() {
  live_player "Naruto Episode 9" naruto-2 9 >/dev/null
  live_player "Frieren Episode 3" frieren-1 3 >/dev/null
  assert_eq "$("$OMANI" players | wc -l)" "2"
}

t_the_players_file_does_not_grow_without_end() {
  local i
  for i in $(seq 1 25); do
    OMANI_DRY_RUN='' OMANI_PLAYER=true "$OMANI" play frieren-1 "Frieren" "$i" >/dev/null
  done
  local lines
  lines=$(wc -l <"$OMANI_STATE_DIR/players")
  ((lines <= 20)) || fail "$current" "the players file holds $lines records"
}

t_resume_reports_a_provider_that_refuses_the_episode() {
  cat >"$WORK/provider" <<'FAKE'
#!/bin/bash
case "$1" in
episodes) printf '9001\t1\n' ;;
stream)
  printf 'omani-provider: episode %s not found\n' "$3" >&2
  exit 1
  ;;
esac
FAKE
  chmod +x "$WORK/provider"
  seed_history '{"frieren-1": {"title": "Frieren", "episode": "99", "episodes": {"99": {"position": 10, "duration": 1400}}}}'
  local out
  out=$("$OMANI" resume frieren-1 2>&1)
  assert_fails $?
  assert_contains "$out" "could not resolve episode 99"
}

t_a_player_waiting_to_be_reaped_is_not_playing() {
  bash -c 'sleep 0.1 & exec sleep 5' &
  local parent=$!
  printf '%s\n' "$parent" >>"$WORK/spawned"
  sleep 0.6
  local zombie candidate stat fields
  for candidate in $(pgrep -P "$parent" 2>/dev/null); do
    stat=$(cat "/proc/$candidate/stat" 2>/dev/null) || continue
    stat=${stat#*") "}
    read -ra fields <<<"$stat"
    [[ ${fields[0]} == Z ]] && zombie=$candidate && break
  done
  [[ -n ${zombie:-} ]] || fail "$current" "no zombie among the children"
  mkdir -p "$OMANI_STATE_DIR"
  printf '%s\tZombie Episode 1\tzombie-1\t1\t\t%s\n' "$zombie" "$(started_at "$zombie")" >>"$OMANI_STATE_DIR/players"
  assert_lacks "$("$OMANI" players)" "Zombie"
  kill "$parent" 2>/dev/null
}

t_players_says_nothing_on_stderr_about_a_pid_that_is_gone() {
  local pid
  pid=$(live_player "Frieren Episode 3" frieren-1 3)
  kill "$pid" 2>/dev/null
  wait_until_gone "$pid"
  local noise
  noise=$("$OMANI" players 2>&1 >/dev/null)
  assert_eq "$noise" ""
}

t_an_episode_watched_to_exactly_the_threshold_restarts() {
  seed_history '{"frieren-1": {"title": "Frieren", "episode": "1", "episodes": {"1": {"position": 1260, "duration": 1400}}}}'
  assert_lacks "$("$OMANI" play frieren-1 "Frieren" 1)" "--start="
}

t_an_episode_a_second_short_of_the_threshold_resumes() {
  seed_history '{"frieren-1": {"title": "Frieren", "episode": "1", "episodes": {"1": {"position": 1259, "duration": 1400}}}}'
  assert_contains "$("$OMANI" play frieren-1 "Frieren" 1)" "--start=1259"
}

t_stop_ends_a_player_that_ignores_being_asked() {
  bash -c 'trap "" TERM; while :; do sleep 0.2; done' >/dev/null 2>&1 &
  local pid=$!
  disown
  printf '%s\n' "$pid" >>"$WORK/spawned"
  mkdir -p "$OMANI_STATE_DIR"
  printf '%s\tStubborn Episode 1\tstubborn-1\t1\t1080\t%s\n' "$pid" "$(awk '{print $22}' "/proc/$pid/stat")" \
    >>"$OMANI_STATE_DIR/players"

  OMANI_DRY_RUN='' "$OMANI" stop stubborn-1 >/dev/null 2>&1

  still_running "$pid" && fail "$current" "the player ignored the stop and is still running"
  assert_lacks "$(cat "$OMANI_STATE_DIR/players")" "Stubborn Episode 1"
}

t_a_record_without_qualities_is_kept_and_can_be_stopped() {
  sleep 60 &
  local pid=$!
  printf '%s\n' "$pid" >>"$WORK/spawned"
  mkdir -p "$OMANI_STATE_DIR"
  printf '%s\tOldest Episode 1\toldest-1\t1\n' "$pid" >>"$OMANI_STATE_DIR/players"
  assert_contains "$("$OMANI" players)" "Oldest Episode 1"

  OMANI_DRY_RUN='' "$OMANI" play frieren-1 "Frieren" 4 >/dev/null 2>&1
  assert_contains "$("$OMANI" players)" "Oldest Episode 1"
  assert_eq "$("$OMANI" stop oldest-1)" "stop $pid"
}

t_play_refuses_a_start_that_is_not_whole_seconds() {
  local out
  out=$("$OMANI" play frieren-1 "Frieren" 1 half 2>&1)
  local code=$?
  ((code != 0)) || fail "$current" "accepted a start that is not seconds"
  assert_contains "$out" "whole seconds"
}

t_a_record_from_an_older_version_still_counts_while_alive() {
  sleep 60 &
  local pid=$!
  printf '%s\n' "$pid" >>"$WORK/spawned"
  mkdir -p "$OMANI_STATE_DIR"
  printf '%s\tOlder Episode 3\tolder-1\t3\t1080\n' "$pid" >>"$OMANI_STATE_DIR/players"
  assert_contains "$("$OMANI" players)" "Older Episode 3"
  assert_eq "$("$OMANI" stop older-1)" "stop $pid"
}

t_players_omits_one_that_exited() {
  live_player "Naruto Episode 9" naruto-2 9 >/dev/null
  printf '999999\tGhost Episode 1\tghost-0\t1\n' >>"$OMANI_STATE_DIR/players"
  local out
  out=$("$OMANI" players)
  assert_contains "$out" "Naruto Episode 9"
  assert_lacks "$out" "Ghost"
}

t_replaying_an_episode_keeps_one_record() {
  OMANI_DRY_RUN='' OMANI_PLAYER=true "$OMANI" play frieren-1 "Frieren" 3
  OMANI_DRY_RUN='' OMANI_PLAYER=true "$OMANI" play frieren-1 "Frieren" 3
  assert_eq "$(grep -c 'Frieren Episode 3' "$OMANI_STATE_DIR/players")" "1"
}

t_playing_a_second_episode_keeps_both_records() {
  OMANI_DRY_RUN='' OMANI_PLAYER=true "$OMANI" play frieren-1 "Frieren" 3
  OMANI_DRY_RUN='' OMANI_PLAYER=true "$OMANI" play naruto-2 "Naruto" 9
  assert_eq "$(wc -l <"$OMANI_STATE_DIR/players")" "2"
}

t_stop_targets_one_player_by_pid() {
  live_player "Naruto Episode 9" naruto-2 9 >/dev/null
  local second
  second=$(live_player "Frieren Episode 3" frieren-1 3)
  assert_eq "$("$OMANI" stop "$second")" "stop $second"
}

t_stop_targets_one_player_by_title() {
  local pid
  pid=$(live_player "Naruto Episode 9" naruto-2 9)
  assert_eq "$("$OMANI" stop "Naruto Episode 9")" "stop $pid"
}

t_stop_targets_a_series_by_its_id() {
  local pid
  pid=$(live_player "Naruto Episode 9" naruto-2 9)
  assert_eq "$("$OMANI" stop naruto-2)" "stop $pid"
}

t_stop_by_id_leaves_other_series_alone() {
  local naruto frieren
  naruto=$(live_player "Naruto Episode 9" naruto-2 9)
  frieren=$(live_player "Frieren Episode 3" frieren-1 3)
  local out
  out=$("$OMANI" stop frieren-1)
  assert_eq "$out" "stop $frieren"
  assert_lacks "$out" "$naruto"
}

t_stop_leaves_a_pid_that_is_no_longer_its_player() {
  sleep 60 &
  local victim=$!
  printf '%s\n' "$victim" >>"$WORK/spawned"
  mkdir -p "$OMANI_STATE_DIR"
  printf '%s\tImpostor Episode 1\timpostor-1\t1\t\t1\n' "$victim" >>"$OMANI_STATE_DIR/players"
  assert_contains "$(cat "$OMANI_STATE_DIR/players")" "impostor-1"
  OMANI_DRY_RUN='' "$OMANI" stop impostor-1
  sleep 0.2
  still_running "$victim" || fail "$current" "stop killed a process the record no longer names"
  kill "$victim" 2>/dev/null
}

t_stop_matches_a_title_holding_a_backslash() {
  local pid
  pid=$(live_player 'A\D Episode 1' tricky-3 1)
  assert_eq "$("$OMANI" stop 'A\D Episode 1')" "stop $pid"
}

t_stop_all_targets_every_player() {
  local first second
  first=$(live_player "Naruto Episode 9" naruto-2 9)
  second=$(live_player "Frieren Episode 3" frieren-1 3)
  local out
  out=$("$OMANI" stop all)
  assert_contains "$out" "$first"
  assert_contains "$out" "$second"
}

t_stop_forgets_the_player_it_stopped() {
  live_player "Naruto Episode 9" naruto-2 9 >/dev/null
  local second
  second=$(live_player "Frieren Episode 3" frieren-1 3)
  OMANI_DRY_RUN='' "$OMANI" stop "$second"
  local left
  left=$(cat "$OMANI_STATE_DIR/players")
  assert_contains "$left" "Naruto"
  assert_lacks "$left" "Frieren"
}

t_a_record_whose_player_is_gone_is_pruned_by_the_next_one() {
  local first
  first=$(live_player "Frieren Episode 3" frieren-1 3)
  kill "$first" 2>/dev/null
  wait_until_gone "$first"
  OMANI_DRY_RUN='' OMANI_PLAYER="$WORK/player" "$OMANI" play naruto-2 "Naruto" 9
  cut -f1 "$OMANI_STATE_DIR/players" >>"$WORK/spawned"
  assert_eq "$("$OMANI" players | wc -l)" "1"
  assert_contains "$("$OMANI" players)" "Naruto Episode 9"
}

t_stop_an_unknown_player_is_not_an_error() {
  live_player "Naruto Episode 9" naruto-2 9 >/dev/null
  "$OMANI" stop 999
  assert_ok $?
}

t_stop_without_any_player_is_not_an_error() {
  "$OMANI" stop all
  assert_ok $?
}

t_writes_do_not_depend_on_tmpdir() {
  export TMPDIR="$WORK/absent"
  OMANI_DRY_RUN='' "$OMANI" progress frieren-1 2 30 1400
  assert_ok $?
  OMANI_DRY_RUN='' OMANI_PLAYER="$WORK/player" "$OMANI" play frieren-1 "Frieren" 3
  assert_ok $?
  unset TMPDIR
  assert_eq "$(series_field frieren-1 '.episodes["2"].position')" "30"
  assert_eq "$(wc -l <"$OMANI_STATE_DIR/players")" "1"
}

t_a_write_leaves_no_temporary_file_behind() {
  OMANI_DRY_RUN='' "$OMANI" progress frieren-1 2 30 1400
  local leftovers
  leftovers=$(find "$(dirname "$OMANI_HIST_FILE")" -name "$(basename "$OMANI_HIST_FILE").??????" | wc -l)
  assert_eq "$leftovers" "0"
}

t_next_refuses_when_the_episode_is_no_longer_listed() {
  seed_history '{"frieren-1": {"title": "Frieren", "episode": "99", "episodes": {}}}'
  local out
  out=$("$OMANI" next frieren-1 2>&1)
  assert_fails $?
  assert_contains "$out" "no episode after"
}

t_resume_after_forgetting_the_series_fails_cleanly() {
  OMANI_DRY_RUN='' "$OMANI" forget frieren-1
  local out
  out=$("$OMANI" resume frieren-1 2>&1)
  assert_fails $?
  assert_contains "$out" "not in history"
}

t_an_episode_number_carrying_a_backslash_still_steps() {
  cat >"$WORK/provider" <<'FAKE'
#!/bin/bash
case "$1" in
episodes) printf '9001\t1\n9002\t2\\x\n9003\t3\n' ;;
stream) printf 'url\thttps://cdn/%s/%s.m3u8\nreferrer\thttps://e/\n' "$2" "$3" ;;
esac
FAKE
  chmod +x "$WORK/provider"
  seed_history '{"frieren-1": {"title": "Frieren", "episode": "2\\x", "episodes": {}}}'
  local out
  out=$("$OMANI" next frieren-1 2>&1)
  assert_contains "$out" "Frieren Episode 3"
  out=$("$OMANI" previous frieren-1 2>&1)
  assert_contains "$out" "Frieren Episode 1"
}

t_an_episode_number_carrying_a_decimal_plays() {
  cat >"$WORK/provider" <<'FAKE'
#!/bin/bash
case "$1" in
episodes) printf '9001	7
9002	7.5
9003	8
' ;;
stream) printf 'url	https://cdn/%s/%s.m3u8
referrer	https://embed/
' "$2" "$3" ;;
esac
FAKE
  chmod +x "$WORK/provider"
  seed_history '{"frieren-1": {"title": "Frieren", "episode": "7", "episodes": {}}}'
  assert_contains "$("$OMANI" next frieren-1)" "Frieren Episode 7.5"
  seed_history '{"frieren-1": {"title": "Frieren", "episode": "7.5", "episodes": {}}}'
  assert_contains "$("$OMANI" next frieren-1)" "Frieren Episode 8"
  assert_contains "$("$OMANI" previous frieren-1)" "Frieren Episode 7"
}

t_progress_reports_arriving_together_are_not_lost() {
  local i
  for i in 1 2 3 4 5 6 7 8; do
    OMANI_DRY_RUN='' "$OMANI" progress frieren-1 "$i" $((i * 10)) 1400 &
    OMANI_DRY_RUN='' "$OMANI" progress naruto-2 "$i" $((i * 10)) 1400 &
  done
  wait
  assert_eq "$(series_field frieren-1 '.episodes | length')" "8"
  assert_eq "$(series_field naruto-2 '.episodes | length')" "8"
  assert_eq "$(series_field frieren-1 '.episodes["8"].position')" "80"
}

t_a_title_holding_a_line_break_keeps_the_record_readable() {
  OMANI_DRY_RUN='' OMANI_PLAYER=true "$OMANI" play broken-9 "$(printf 'A\nB')" 3
  assert_eq "$(wc -l <"$OMANI_STATE_DIR/players")" "1"
  assert_eq "$(awk -F'\t' '$3 == "broken-9" { print $2 }' "$OMANI_STATE_DIR/players")" "A B Episode 3"
}

t_one_unreadable_record_does_not_hide_the_others() {
  local pid
  pid=$(live_player "Frieren Episode 3" frieren-1 3)
  printf 'not a record\n' >>"$OMANI_STATE_DIR/players"
  printf '123\n' >>"$OMANI_STATE_DIR/players"
  local out
  out=$("$OMANI" players 2>&1)
  assert_contains "$out" "Frieren Episode 3"
  assert_lacks "$out" "unbound"
  printf '%s\n' "$pid" >>"$WORK/spawned"
}

t_a_title_holding_a_tab_keeps_the_record_readable() {
  OMANI_DRY_RUN='' OMANI_PLAYER=true "$OMANI" play tabbed-9 "$(printf 'A\tB')" 3
  local fields
  fields=$(awk -F'\t' '$3 == "tabbed-9" { print NF }' "$OMANI_STATE_DIR/players")
  assert_eq "$fields" "6"
  assert_eq "$(awk -F'\t' '$3 == "tabbed-9" { print $4 }' "$OMANI_STATE_DIR/players")" "3"
}

t_a_first_play_creates_the_history() {
  rm -f "$OMANI_HIST_FILE"
  OMANI_DRY_RUN='' OMANI_PLAYER=true "$OMANI" play frieren-1 "Frieren" 1
  assert_ok $?
  assert_file "$OMANI_HIST_FILE"
  assert_eq "$(series_field frieren-1 .episode)" "1"
}

t_forgetting_the_last_series_leaves_a_history_that_reads() {
  OMANI_DRY_RUN='' "$OMANI" forget frieren-1
  OMANI_DRY_RUN='' "$OMANI" forget naruto-2
  assert_eq "$("$OMANI" history | jq -r '.series | length')" "0"
  assert_eq "$("$OMANI" history | jq -r '.version')" "1"
}

t_status_survives_a_missing_players_file() {
  rm -rf "$OMANI_STATE_DIR"
  assert_eq "$("$OMANI" players | wc -l)" "0"
  assert_ok $?
  assert_eq "$("$OMANI" status | jq -r .playersPath)" "$OMANI_STATE_DIR/players"
}

t_clearing_an_already_empty_history_keeps_it_valid() {
  OMANI_DRY_RUN='' "$OMANI" history-clear
  OMANI_DRY_RUN='' "$OMANI" history-clear
  assert_ok $?
  assert_eq "$("$OMANI" history | jq -r '.series | length')" "0"
}

t_history_clear_empties_and_backs_up() {
  OMANI_DRY_RUN='' "$OMANI" history-clear
  assert_ok $?
  assert_eq "$("$OMANI" history | jq -r '.series | length')" "0"
  assert_file "$OMANI_HIST_FILE.bak"
  assert_contains "$(cat "$OMANI_HIST_FILE.bak")" "frieren-1"
}

t_history_clear_on_an_absent_history_is_not_an_error() {
  rm -f "$OMANI_HIST_FILE"
  OMANI_DRY_RUN='' "$OMANI" history-clear
  assert_ok $?
}

t_unknown_subcommand_fails_loudly() {
  local out
  out=$("$OMANI" not-a-subcommand 2>&1)
  assert_fails $?
  assert_contains "$out" "unknown"
}

t_no_subcommand_prints_usage() {
  local out
  out=$("$OMANI" 2>&1)
  assert_fails $?
  assert_contains "$out" "usage"
}

t_help_succeeds() {
  local out
  out=$("$OMANI" --help 2>&1)
  assert_ok $?
  assert_contains "$out" "usage"
}

check "status is valid json" t_status_json
check "status reports the history path" t_status_reports_the_history_path
check "status reports the repository" t_status_reports_the_repository
check "status reports the plugin version" t_status_reports_the_plugin_version
check "status survives a missing manifest" t_status_survives_a_missing_manifest
check "status names a player that is missing" t_status_names_a_missing_player
check "status reads the real script directories when nothing overrides them" t_status_uses_the_real_script_dirs_by_default
check "mpris loaded by path in mpv.conf counts" t_status_finds_mpris_loaded_by_path_in_the_config
check "an unrelated script line does not count" t_status_ignores_an_unrelated_script_line
check "status names mpv-mpris when the script is absent" t_status_names_mpv_mpris_when_absent
check "mpris found in any configured script directory counts" t_status_accepts_mpris_from_any_script_dir
check "search passes provider rows through" t_search_returns_provider_rows
check "episodes passes provider rows through" t_episodes_returns_provider_rows
check "play builds a player command" t_play_builds_a_player_command
check "the requested quality reaches the provider" t_play_asks_the_provider_for_the_requested_quality
check "no requested quality asks the provider for best" t_play_without_a_quality_asks_for_the_default
check "play passes subtitles when the provider offers them" t_play_passes_subtitles_when_offered
check "play omits the subtitle flag when there are none" t_play_omits_subtitles_when_absent
check "play needs an id, a title and an episode" t_play_needs_all_three_arguments
check "play drops a subtitle that is not a web address" t_play_drops_a_subtitle_that_is_not_a_web_address
check "play keeps a subtitle that is a web address" t_play_keeps_a_subtitle_that_is_a_web_address
check "play refuses a url the provider should not have sent" t_play_refuses_a_url_the_provider_should_not_have_sent
check "the player is told where its arguments end" t_the_player_is_told_where_its_arguments_end
check "play fails when no source resolves" t_play_fails_when_no_source_resolves
check "play records a series not seen before" t_play_records_a_new_series
check "play advances a series already in history" t_play_advances_a_series_already_watched
check "history timestamps are finer than a second" t_history_timestamps_are_finer_than_a_second
check "a record carries when its player started" t_a_record_carries_when_its_player_started
check "a player that exits at once leaves a record and no noise" t_a_player_that_exits_at_once_leaves_a_record_and_no_noise
check "a player pid taken over by something else is not listed" t_a_player_pid_taken_over_by_something_else_is_not_listed
check "play leaves other series alone" t_play_leaves_other_series_alone
check "history survives a title with punctuation" t_history_survives_a_title_with_punctuation
check "progress records how far into an episode you are" t_progress_records_how_far_in_you_are
check "finishing an episode moves the series on" t_finishing_an_episode_moves_the_series_on
check "the threshold that finishes an episode can be set" t_the_threshold_that_finishes_an_episode_can_be_set
check "a threshold that is not a percentage falls back" t_a_threshold_that_is_not_a_percentage_falls_back
check "the next episode is looked up once, not on every report" t_finishing_looks_up_the_next_episode_once
check "part way through leaves the series where it is" t_part_way_through_leaves_the_series_where_it_is
check "each episode keeps its own position" t_progress_keeps_each_episode_apart
check "reporting the same episode again replaces its position" t_progress_replaces_the_position_of_the_same_episode
check "progress refuses a series not in history" t_progress_refuses_a_series_not_in_history
check "progress refuses a position that is not seconds" t_progress_refuses_a_position_that_is_not_seconds
check "resume restarts the episode where it stopped" t_resume_restarts_the_episode_where_it_stopped
check "resume moves on when the episode was nearly finished" t_resume_moves_on_when_the_episode_was_nearly_finished
check "a series with no progress plays the episode it is on" t_a_series_with_no_progress_plays_the_episode_it_is_on
check "resume plays the episode after one watched to the end" t_resume_plays_the_episode_after_one_watched_to_the_end
check "resume refuses a series not in history" t_resume_refuses_an_unknown_series
check "resume refuses when nothing follows" t_resume_refuses_when_nothing_follows
check "next plays the episode after the one watched" t_next_plays_the_episode_after_the_one_watched
check "next moves on from an episode barely started" t_next_moves_on_from_an_episode_barely_started
check "next leaves the progress of the episode it leaves" t_next_leaves_the_progress_of_the_episode_it_leaves
check "a history that cannot be written is said so" t_a_history_that_cannot_be_written_is_said_so
check "a history that does not parse is never written over" t_a_history_that_does_not_parse_is_never_written_over
check "next steps from the newest player of a series" t_next_steps_from_the_newest_player_of_a_series
check "next steps from the episode actually playing" t_next_steps_from_the_episode_actually_playing
check "a history carrying trailing garbage reads as empty" t_a_history_that_carries_trailing_garbage_reads_as_empty
check "next refuses at the last episode" t_next_refuses_at_the_last_episode
check "next refuses a series not in history" t_next_refuses_an_unknown_series
check "previous plays the episode before the one watched" t_previous_plays_the_episode_before_the_one_watched
check "previous resumes an episode left part way" t_previous_resumes_an_episode_left_part_way
check "previous restarts an episode already watched" t_previous_restarts_an_episode_already_watched
check "previous starts an episode never opened at the beginning" t_previous_starts_an_episode_never_opened_at_the_beginning
check "next resumes an episode left part way" t_next_resumes_an_episode_left_part_way
check "a position that is not a count of seconds starts from the beginning" t_a_position_that_is_not_a_count_of_seconds_starts_from_the_beginning
check "a position past the end counts as watched" t_a_position_past_the_end_counts_as_watched
check "a position with no duration is still where it was left" t_a_position_with_no_duration_is_still_where_it_was_left
check "an episodes field that is not an object starts from the beginning" t_an_episodes_field_that_is_not_an_object_starts_from_the_beginning
check "choosing an episode picks it up where it was left" t_choosing_an_episode_picks_it_up_where_it_was_left
check "choosing an episode watched to the end starts it again" t_choosing_an_episode_watched_to_the_end_starts_it_again
check "replay starts at the beginning however far in you were" t_replay_starts_at_the_beginning_however_far_in_you_were
check "previous refuses at the first episode" t_previous_refuses_at_the_first_episode
check "previous refuses a series not in history" t_previous_refuses_an_unknown_series
check "the recorded pid is the player itself" t_the_recorded_pid_is_the_player_itself
check "stop closes the player" t_stop_closes_the_player
check "resume closes the player the series already has" t_resume_closes_the_player_the_series_already_has
check "one player per series, whoever asks" t_one_player_per_series_whoever_asks
check "another series adds a player rather than replacing one" t_another_series_adds_a_player_rather_than_replacing_one
check "play records the player it started" t_play_records_the_player_it_started
check "two episodes are tracked at once" t_two_episodes_are_tracked_at_once
check "the players file does not grow without end" t_the_players_file_does_not_grow_without_end
check "resume reports a provider that refuses the episode" t_resume_reports_a_provider_that_refuses_the_episode
check "a player waiting to be reaped is not playing" t_a_player_waiting_to_be_reaped_is_not_playing
check "players says nothing on stderr about a pid that is gone" t_players_says_nothing_on_stderr_about_a_pid_that_is_gone
check "an episode watched to exactly the threshold restarts" t_an_episode_watched_to_exactly_the_threshold_restarts
check "an episode a second short of the threshold resumes" t_an_episode_a_second_short_of_the_threshold_resumes
check "stop ends a player that ignores being asked" t_stop_ends_a_player_that_ignores_being_asked
check "a record without qualities is kept and can be stopped" t_a_record_without_qualities_is_kept_and_can_be_stopped
check "play refuses a start that is not whole seconds" t_play_refuses_a_start_that_is_not_whole_seconds
check "a record from an older version still counts while alive" t_a_record_from_an_older_version_still_counts_while_alive
check "players omits one that has exited" t_players_omits_one_that_exited
check "replaying an episode keeps one record" t_replaying_an_episode_keeps_one_record
check "playing a second episode keeps both records" t_playing_a_second_episode_keeps_both_records
check "stop targets one player by pid" t_stop_targets_one_player_by_pid
check "stop targets one player by title" t_stop_targets_one_player_by_title
check "stop targets a series by its id" t_stop_targets_a_series_by_its_id
check "stop by id leaves another series playing" t_stop_by_id_leaves_other_series_alone
check "stop leaves a pid that is no longer its player" t_stop_leaves_a_pid_that_is_no_longer_its_player
check "stop matches a title holding a backslash" t_stop_matches_a_title_holding_a_backslash
check "stop all targets every player" t_stop_all_targets_every_player
check "stop forgets the player it stopped" t_stop_forgets_the_player_it_stopped
check "a record whose player is gone is pruned by the next one" t_a_record_whose_player_is_gone_is_pruned_by_the_next_one
check "stopping an unknown player is not an error" t_stop_an_unknown_player_is_not_an_error
check "stopping with no players is not an error" t_stop_without_any_player_is_not_an_error
check "forget drops one series and leaves the rest" t_forget_drops_one_series
check "a report racing a forget does not bring the series back" t_a_report_racing_a_forget_does_not_bring_the_series_back
check "forget refuses a series not in history" t_forget_refuses_a_series_not_in_history
check "forget needs an id" t_forget_needs_an_id
check "a write does not depend on TMPDIR being usable" t_writes_do_not_depend_on_tmpdir
check "a write leaves no temporary file behind" t_a_write_leaves_no_temporary_file_behind
check "a player record leaves no temporary file behind" t_a_player_record_leaves_no_temporary_file_behind
check "a player list that cannot be written is said so" t_a_player_list_that_cannot_be_written_is_said_so
check "next refuses when the episode is no longer listed" t_next_refuses_when_the_episode_is_no_longer_listed
check "resume after forgetting the series fails cleanly" t_resume_after_forgetting_the_series_fails_cleanly
check "an episode number carrying a backslash still steps" t_an_episode_number_carrying_a_backslash_still_steps
check "an episode number carrying a decimal plays" t_an_episode_number_carrying_a_decimal_plays
check "progress reports arriving together are not lost" t_progress_reports_arriving_together_are_not_lost
check "a title holding a line break keeps the record readable" t_a_title_holding_a_line_break_keeps_the_record_readable
check "one unreadable record does not hide the others" t_one_unreadable_record_does_not_hide_the_others
check "a title holding a tab keeps the player record readable" t_a_title_holding_a_tab_keeps_the_record_readable
check "a first play creates the history" t_a_first_play_creates_the_history
check "forgetting the last series leaves a history that reads" t_forgetting_the_last_series_leaves_a_history_that_reads
check "status survives a missing players file" t_status_survives_a_missing_players_file
check "clearing an already empty history keeps it valid" t_clearing_an_already_empty_history_keeps_it_valid
check "clearing refuses when the backup cannot be written" t_clearing_refuses_when_the_backup_cannot_be_written
check "history-clear empties the file and backs it up" t_history_clear_empties_and_backs_up
check "history-clear on an absent history is not an error" t_history_clear_on_an_absent_history_is_not_an_error
check "an unknown subcommand fails loudly" t_unknown_subcommand_fails_loudly
check "no subcommand prints usage" t_no_subcommand_prints_usage
check "help succeeds" t_help_succeeds

printf '\n%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
