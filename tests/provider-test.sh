#!/bin/bash

set -uo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PROVIDER="$ROOT/bin/omani-provider"
FIXTURES="$ROOT/tests/fixtures"

export FIXTURES="$FIXTURES"
export OMANI_CURL="$FIXTURES/fake-curl"

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

assert_eq() {
  [[ $1 == "$2" ]] && return 0
  fail "$current" "expected '$2', got '$1'"
}

assert_contains() {
  [[ $1 == *"$2"* ]] && return 0
  fail "$current" "expected output to contain '$2', got: $1"
}

check() {
  current="$1"
  shift
  local before=$failed
  "$@"
  ((failed == before)) && pass "$current"
}

t_search_rows() {
  local out
  out=$("$PROVIDER" parse-search <"$FIXTURES/search.html")
  assert_eq "$(wc -l <<<"$out")" "4"
  assert_contains "$out" "frieren-beyond-journeys-end-481	Frieren: Beyond Journey's End"
}

t_search_decodes_html_entities() {
  local out
  out=$(printf '<div class="film-detail"><h3 class="film-name"><a href="/watch/x-1" title="Tom &amp; Jerry &#039;s &quot;Day&quot;"></h3>\n' |
    "$PROVIDER" parse-search)
  assert_contains "$out" "Tom & Jerry 's \"Day\""
}

t_search_stops_at_the_sidebar() {
  local out
  out=$(printf '<div class="film-detail"><h3 class="film-name"><a href="/watch/a-1" title="A"></h3>\n<div id="main-sidebar"><div class="film-detail"><h3 class="film-name"><a href="/watch/a-1" title="A"></h3></div>\n' |
    "$PROVIDER" parse-search)
  assert_eq "$(wc -l <<<"$out")" "1"
}

t_episode_rows() {
  local out
  out=$("$PROVIDER" parse-episodes 'frieren-beyond-journeys-end-481' <"$FIXTURES/episodes.json")
  assert_contains "$out" "9227	1"
  assert_contains "$out" "9228	2"
}

t_episodes_ignore_another_series() {
  local out
  out=$("$PROVIDER" parse-episodes 'some-other-show-99' <"$FIXTURES/episodes.json")
  assert_eq "$out" ""
}

t_deobfuscate_round_trip() {
  # The fixture is base64(json XOR "otaku-embed-v1"), committed once, so the
  # suite needs no interpreter to produce it.
  local out expected_src expected_default
  out=$("$PROVIDER" deobfuscate "$(cat "$FIXTURES/embed-blob.txt")")
  expected_src='"src":"https://cdn/master.m3u8"'
  expected_default='"default":true'
  assert_contains "$out" "$expected_src"
  assert_contains "$out" "$expected_default"
}

t_qualities_sorted_best_first() {
  local out
  out=$(printf '#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=640x360,FRAME-RATE=24.000\n360/index.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=2,RESOLUTION=1920x1080,FRAME-RATE=24.000\n1080/index.m3u8\n' |
    "$PROVIDER" parse-qualities "https://host/path/master.m3u8")
  assert_eq "$(head -1 <<<"$out")" "1080p >https://host/path/1080/index.m3u8"
}

t_qualities_keep_absolute_urls() {
  local out
  out=$(printf '#EXT-X-STREAM-INF:RESOLUTION=1280x720,FRAME-RATE=24.000\nhttps://cdn/720.m3u8\n' |
    "$PROVIDER" parse-qualities "https://host/path/master.m3u8")
  assert_eq "$out" "720p >https://cdn/720.m3u8"
}

t_qualities_drop_iframe_variants() {
  local out
  out=$(printf '#EXT-X-I-FRAME-STREAM-INF:RESOLUTION=1920x1080,URI="if.m3u8"\n#EXT-X-STREAM-INF:RESOLUTION=1280x720,FRAME-RATE=24.000\n720/i.m3u8\n' |
    "$PROVIDER" parse-qualities "https://host/p/master.m3u8")
  assert_eq "$(wc -l <<<"$out")" "1"
  assert_contains "$out" "720p"
}

t_usage_without_a_subcommand() {
  local out
  if out=$("$PROVIDER" 2>&1); then
    fail "$current" "expected a non-zero exit"
  fi
  assert_contains "$out" "usage"
}

t_search_end_to_end() {
  local out
  out=$("$PROVIDER" search frieren) || fail "$current" "search failed"
  assert_contains "$out" "frieren-beyond-journeys-end-481"
}

t_search_reports_a_cloudflare_block() {
  local out
  if out=$(FAKE_CLOUDFLARE=1 "$PROVIDER" search frieren 2>&1); then
    fail "$current" "expected failure"
  fi
  assert_contains "$out" "cloudflare"
}

t_episodes_reports_a_cloudflare_block() {
  local out
  if out=$(FAKE_CLOUDFLARE=1 FAKE_CODE=403 "$PROVIDER" episodes frieren-beyond-journeys-end-481 2>&1); then
    fail "$current" "expected a non-zero exit"
  fi
  assert_contains "$out" "cloudflare"
}

t_stream_reports_a_cloudflare_block() {
  local out
  if out=$(FAKE_CLOUDFLARE=1 FAKE_CODE=403 "$PROVIDER" stream frieren-beyond-journeys-end-481 1 sub best 2>&1); then
    fail "$current" "expected a non-zero exit"
  fi
  assert_contains "$out" "cloudflare"
}

t_quality_is_matched_on_its_height_not_the_url() {
  # The 1080 variant's url carries "720" in a path segment.
  local out
  out=$(FAKE_MASTER="$FIXTURES/master-decoy.m3u8" "$PROVIDER" stream frieren-beyond-journeys-end-481 1 sub 720)
  assert_contains "$out" "url	https://cdn/plain/720/i.m3u8"
}

t_search_reports_a_transport_failure() {
  local out
  if out=$(FAKE_CURL_FAIL=1 "$PROVIDER" search frieren 2>&1); then
    fail "$current" "expected a non-zero exit"
  fi
  assert_contains "$out" "could not fetch"
}

t_search_reports_a_bad_status() {
  local out
  if out=$(FAKE_CODE=503 "$PROVIDER" search frieren 2>&1); then
    fail "$current" "expected a non-zero exit"
  fi
  assert_contains "$out" "503"
}

t_search_needs_a_query() {
  local out
  out=$("$PROVIDER" search 2>&1)
  assert_contains "$out" "usage"
}

t_episodes_end_to_end() {
  assert_contains "$("$PROVIDER" episodes frieren-beyond-journeys-end-481)" "9227	1"
}

t_episodes_needs_an_id() {
  local out
  out=$("$PROVIDER" episodes 2>&1)
  assert_contains "$out" "usage"
}

t_stream_resolves_url_referrer_and_subtitles() {
  local out
  out=$("$PROVIDER" stream frieren-beyond-journeys-end-481 1 sub best)
  assert_contains "$out" "url	https://cdn/1080/i.m3u8"
  assert_contains "$out" "referrer	https://zokoanime.video/"
  assert_contains "$out" "subtitles	https://cdn/en.vtt"
}

t_stream_reports_the_variants_the_episode_has() {
  local out
  out=$("$PROVIDER" stream frieren-beyond-journeys-end-481 1 sub best)
  assert_contains "$out" "qualities	1080 360"
}

t_stream_honours_the_requested_quality() {
  assert_contains "$("$PROVIDER" stream frieren-beyond-journeys-end-481 1 sub 360)" "url	https://cdn/360/i.m3u8"
}

t_stream_falls_back_when_the_quality_is_absent() {
  assert_contains "$("$PROVIDER" stream frieren-beyond-journeys-end-481 1 sub 4320)" "url	https://cdn/1080/i.m3u8"
}

t_stream_takes_the_worst_when_asked() {
  assert_contains "$("$PROVIDER" stream frieren-beyond-journeys-end-481 1 sub worst)" "url	https://cdn/360/i.m3u8"
}

t_stream_refuses_an_episode_that_is_not_listed() {
  local out
  if out=$("$PROVIDER" stream frieren-beyond-journeys-end-481 999 sub best 2>&1); then
    fail "$current" "expected failure"
  fi
  assert_contains "$out" "episode 999 not found"
}

t_stream_refuses_a_mode_with_no_source() {
  local out
  out=$("$PROVIDER" stream frieren-beyond-journeys-end-481 1 dub best 2>&1)
  assert_contains "$out" "no ZokoAnime source for dub"
}

t_stream_reports_a_server_list_without_a_usable_player() {
  printf '<div class="server-item" data-type="sub" data-server-name="SomeOther" data-hash="x"></div>\n' >"$FIXTURES/other-servers.html"
  local out
  out=$(FAKE_SERVERS="$FIXTURES/other-servers.html" "$PROVIDER" stream frieren-beyond-journeys-end-481 1 sub best 2>&1)
  rm -f "$FIXTURES/other-servers.html"
  assert_contains "$out" "no ZokoAnime source"
}

t_stream_needs_an_id_and_an_episode() {
  local out
  out=$("$PROVIDER" stream frieren-1 2>&1)
  assert_contains "$out" "usage"
}

check "search works end to end against saved pages" t_search_end_to_end
check "search reports a cloudflare block" t_search_reports_a_cloudflare_block
check "episodes reports a cloudflare block" t_episodes_reports_a_cloudflare_block
check "stream reports a cloudflare block" t_stream_reports_a_cloudflare_block
check "a quality is matched on its height, not anywhere in the url" t_quality_is_matched_on_its_height_not_the_url
check "search reports a transport failure" t_search_reports_a_transport_failure
check "search reports a bad http status" t_search_reports_a_bad_status
check "search needs a query" t_search_needs_a_query
check "episodes works end to end" t_episodes_end_to_end
check "episodes needs an id" t_episodes_needs_an_id
check "stream resolves url, referrer and subtitles" t_stream_resolves_url_referrer_and_subtitles
check "stream reports the variants the episode has" t_stream_reports_the_variants_the_episode_has
check "stream honours the requested quality" t_stream_honours_the_requested_quality
check "stream falls back when the quality is absent" t_stream_falls_back_when_the_quality_is_absent
check "stream takes the worst when asked" t_stream_takes_the_worst_when_asked
check "stream refuses an episode that is not listed" t_stream_refuses_an_episode_that_is_not_listed
check "stream refuses a mode with no source" t_stream_refuses_a_mode_with_no_source
check "stream reports a server list with no usable player" t_stream_reports_a_server_list_without_a_usable_player
check "stream needs an id and an episode" t_stream_needs_an_id_and_an_episode

check "search rows come back as id and title" t_search_rows
check "search decodes html entities in titles" t_search_decodes_html_entities
check "search stops at the sidebar that repeats results" t_search_stops_at_the_sidebar
check "episode rows come back as id and number" t_episode_rows
check "episodes belonging to another series are ignored" t_episodes_ignore_another_series
check "the embed payload round-trips through deobfuscation" t_deobfuscate_round_trip
check "qualities are sorted best first and made absolute" t_qualities_sorted_best_first
check "an already absolute variant url is left alone" t_qualities_keep_absolute_urls
check "i-frame variants are not offered as qualities" t_qualities_drop_iframe_variants
check "no subcommand prints usage and fails" t_usage_without_a_subcommand

printf '\n%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
