#!/bin/bash

set -uo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
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

argv_spy() {
  local spy
  spy=$(mktemp "$WORK/argvspy.XXXXXX")
  cat >"$spy" <<SPY
#!/bin/sh
printf '%s\n' "\$*" >"$1"
printf ' 200'
SPY
  chmod +x "$spy"
  printf '%s' "$spy"
}

url_spy() {
  local spy
  spy=$(mktemp "$WORK/spy.XXXXXX")
  cat >"$spy" <<SPY
#!/bin/sh
while IFS= read -r line; do
  case \$line in
  'url = '*)
    line=\${line#url = \"}
    printf '%s' "\${line%\"}" >"$1"
    break
    ;;
  esac
done
printf ' 200'
SPY
  chmod +x "$spy"
  printf '%s' "$spy"
}

assert_lacks() {
  [[ $1 != *"$2"* ]] && return 0
  fail "$current" "did not expect '$2' in: $1"
}

assert_missing() {
  [[ ! -e $1 ]] && return 0
  fail "$current" "did not expect the file: $1"
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

t_search_reads_an_anchor_whatever_else_it_carries() {
  local out
  out=$(printf '<div class="film-detail"><h3 class="film-name"><a href="/watch/some-show-12" class="dynamic-name" title="Some Show"></a></h3></div>\n' |
    "$PROVIDER" parse-search)
  assert_eq "$out" "some-show-12	Some Show"
}

t_a_title_holding_a_tab_stays_one_row() {
  local out
  out=$(printf '<div class="film-detail"><h3 class="film-name"><a href="/watch/x-1" title="A\tB"></a></h3></div>\n' |
    "$PROVIDER" parse-search)
  assert_eq "$(awk -F'\t' '{print NF}' <<<"$out")" "2"
}

t_episode_rows_do_not_depend_on_attribute_order() {
  local out
  out=$(printf 'ep-item data-id="9001" data-number="1" href="/watch/frieren-1?ep=9001"\n' |
    "$PROVIDER" parse-episodes "frieren-1")
  assert_eq "$out" "9001	1"
}

t_an_id_carrying_a_regex_character_matches_itself() {
  local out
  out=$(printf 'ep-item data-number="1" data-id="9001" href="/watch/re.zero-1?ep=9001"\n' |
    "$PROVIDER" parse-episodes "re.zero-1")
  assert_eq "$out" "9001	1"
  out=$(printf 'ep-item data-number="1" data-id="9001" href="/watch/rexzero-1?ep=9001"\n' |
    "$PROVIDER" parse-episodes "re.zero-1")
  assert_eq "$out" ""
}

t_a_page_that_is_not_valid_text_is_parsed_without_complaint() {
  local out
  out=$(printf '<div class="film-detail"><h3 class="film-name"><a href="/watch/x-1" title="A\xff\xfeB"></a></h3></div>\n' |
    "$PROVIDER" parse-search 2>&1 >/dev/null)
  assert_eq "$out" ""
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

t_qualities_sorted_best_first() {
  local out
  out=$(printf '#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=640x360,FRAME-RATE=24.000\n360/index.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=2,RESOLUTION=1920x1080,FRAME-RATE=24.000\n1080/index.m3u8\n' |
    "$PROVIDER" parse-qualities "https://host/path/master.m3u8")
  assert_eq "$(head -1 <<<"$out")" "1080p >https://host/path/1080/index.m3u8"
}

t_qualities_survive_tags_between_the_variants() {
  local out
  out=$(printf '#EXTM3U\n#EXT-X-INDEPENDENT-SEGMENTS\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="English",URI="audio/eng.m3u8"\n#EXT-X-STREAM-INF:BANDWIDTH=5300000,RESOLUTION=1920x1080,AUDIO="aud"\n1080/i.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,AUDIO="aud"\n360/i.m3u8\n' |
    "$PROVIDER" parse-qualities "https://host/p/master.m3u8")
  assert_eq "$(wc -l <<<"$out")" "2"
  assert_eq "$(head -1 <<<"$out")" "1080p >https://host/p/1080/i.m3u8"
}

t_a_variant_without_a_resolution_is_left_out() {
  local out
  out=$(printf '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=800000\naudio/i.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=5300000,RESOLUTION=1920x1080\n1080/i.m3u8\n' |
    "$PROVIDER" parse-qualities "https://host/p/master.m3u8")
  assert_eq "$out" "1080p >https://host/p/1080/i.m3u8"
}

t_codecs_carrying_an_x_do_not_swallow_the_height() {
  local out
  out=$(printf '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=5300000,RESOLUTION=1920x1080,CODECS="avc1.64002x,mp4a.40.2"\n1080/i.m3u8\n' |
    "$PROVIDER" parse-qualities "https://host/p/master.m3u8")
  assert_eq "$out" "1080p >https://host/p/1080/i.m3u8"
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
  assert_contains "$out" "referrer	https://megaplay.buzz/"
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

t_a_server_is_found_whatever_order_its_attributes_are_in() {
  local out
  out=$(FAKE_SERVERS="$FIXTURES/servers-reordered.html" "$PROVIDER" stream frieren-beyond-journeys-end-481 1 sub best)
  assert_contains "$out" "url	"
}

t_a_height_does_not_carry_to_the_next_variant() {
  local out
  out=$(printf '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=5300000,RESOLUTION=1920x1080\n#EXT-X-STREAM-INF:BANDWIDTH=800000\naudio/i.m3u8\n' |
    "$PROVIDER" parse-qualities "https://host/p/master.m3u8")
  assert_eq "$out" ""
}

t_one_variant_line_is_offered_per_declaration() {
  local out
  out=$(printf '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=5300000,RESOLUTION=1920x1080\n1080/i.m3u8\nstray/i.m3u8\n' |
    "$PROVIDER" parse-qualities "https://host/p/master.m3u8")
  assert_eq "$out" "1080p >https://host/p/1080/i.m3u8"
}

t_the_first_matching_server_is_the_one_used() {
  local servers="$WORK/two-zoko.html"
  {
    printf '<div class="server-item" data-type="sub" data-server-name="ZokoAnime" data-hash="%s"></div>\n' \
      "$(printf 'https://zokoanime.video/first' | base64 -w0)"
    printf '<div class="server-item" data-type="sub" data-server-name="ZokoAnime" data-hash="%s"></div>\n' \
      "$(printf 'https://zokoanime.video/second' | base64 -w0)"
  } >"$servers"
  local log="$WORK/asked-for"
  : >"$log"
  FAKE_URL_LOG="$log" FAKE_SERVERS="$servers" "$PROVIDER" stream frieren-beyond-journeys-end-481 1 sub best >/dev/null 2>&1
  assert_contains "$(cat "$log")" "https://zokoanime.video/first"
  assert_lacks "$(cat "$log")" "second"
}

t_an_embed_hash_that_is_not_base64_is_refused() {
  local servers="$WORK/bad-hash.html"
  printf '<div class="server-item" data-type="sub" data-server-name="ZokoAnime" data-hash="!!not base64!!"></div>\n' >"$servers"
  local out
  if out=$(FAKE_SERVERS="$servers" "$PROVIDER" stream frieren-beyond-journeys-end-481 1 sub best 2>&1); then
    fail "$current" "expected a non-zero exit"
  fi
  assert_contains "$out" "could not decode the embed url"
}

t_a_playlist_that_names_no_source_is_refused() {
  local out
  if out=$(FAKE_SOURCES="$FIXTURES/sources-no-file.json" "$PROVIDER" stream frieren-beyond-journeys-end-481 1 sub best 2>&1); then
    fail "$current" "expected a non-zero exit"
  fi
  assert_contains "$out" "named no source"
}

t_a_subtitle_that_is_not_a_web_address_is_dropped() {
  local out
  out=$(FAKE_SOURCES="$FIXTURES/sources-local-subtitle.json" "$PROVIDER" stream frieren-beyond-journeys-end-481 1 sub best 2>&1)
  assert_contains "$out" "subtitles	"
  assert_lacks "$out" "passwd"
}

t_a_master_playlist_with_no_variants_is_refused() {
  local master="$WORK/empty.m3u8"
  printf '#EXTM3U\n' >"$master"
  local out
  if out=$(FAKE_MASTER="$master" "$PROVIDER" stream frieren-beyond-journeys-end-481 1 sub best 2>&1); then
    fail "$current" "expected a non-zero exit"
  fi
  assert_contains "$out" "no playable qualities"
}

t_a_cloudflare_block_on_plain_curl_names_the_fix() {
  local bin="$WORK/plaincurl"
  mkdir -p "$bin"
  cp "$FIXTURES/fake-curl" "$bin/curl"
  local out
  out=$(FAKE_CLOUDFLARE=1 PATH="$bin:/usr/bin:/bin" OMANI_CURL=curl "$PROVIDER" search x 2>&1)
  assert_contains "$out" "install curl-impersonate"
}

t_stream_resolves_through_the_source_the_site_now_serves() {
  local out
  out=$(FAKE_SOURCES="$FIXTURES/sources-megaplay.json" "$PROVIDER" stream frieren-beyond-journeys-end-481 1 sub best 2>&1)
  assert_contains "$out" "url	https://fetch.nexabloom.top/"
  assert_contains "$out" "referrer	https://megaplay.buzz/"
  assert_contains "$out" "subtitles	https://"
}

t_a_server_the_site_renames_still_plays() {
  sed 's|Vidstream-2|Vidstream-9|g' "$FIXTURES/servers-vidstream.html" >"$WORK/renamed.html"
  local out
  out=$(FAKE_SERVERS="$WORK/renamed.html" "$PROVIDER" stream frieren-beyond-journeys-end-481 1 sub best 2>&1)
  assert_contains "$out" "url	"
}

t_an_embed_carrying_neither_scheme_is_refused() {
  printf '<html><body>no player here</body></html>
' >"$WORK/blank-embed.html"
  local out
  if out=$(FAKE_EMBED_PAGE="$WORK/blank-embed.html" "$PROVIDER" stream frieren-beyond-journeys-end-481 1 sub best 2>&1); then
    fail "$current" "expected a non-zero exit"
  fi
  assert_contains "$out" "carried no source"
}

t_sources_without_an_encrypted_playlist_are_refused() {
  printf '{"tracks":[]}
' >"$WORK/bare.json"
  local out
  if out=$(FAKE_SOURCES="$WORK/bare.json" "$PROVIDER" stream frieren-beyond-journeys-end-481 1 sub best 2>&1); then
    fail "$current" "expected a non-zero exit"
  fi
  assert_contains "$out" "no encrypted playlist"
}

t_a_playlist_that_will_not_decrypt_is_refused() {
  printf '{"enc":"bm90IGEgcmVhbCBibG9i"}
' >"$WORK/bad.json"
  local out
  if out=$(FAKE_SOURCES="$WORK/bad.json" "$PROVIDER" stream frieren-beyond-journeys-end-481 1 sub best 2>&1); then
    fail "$current" "expected a non-zero exit"
  fi
  assert_contains "$out" "its key has changed"
}

t_usage_names_every_subcommand() {
  local usage sub
  usage=$("$PROVIDER" 2>&1)
  for sub in search episodes stream parse-search parse-episodes parse-qualities; do
    assert_contains "$usage" "$sub"
  done
}

t_a_query_carrying_url_syntax_is_encoded() {
  local asked="$WORK/asked"
  OMANI_CURL=$(url_spy "$asked") "$PROVIDER" search "tom & jerry #1" >/dev/null 2>&1
  assert_contains "$(cat "$asked" 2>/dev/null)" "keyword=tom%20%26%20jerry%20%231"
}

t_a_query_in_another_script_is_encoded_as_utf8() {
  local asked="$WORK/asked-utf8"
  OMANI_CURL=$(url_spy "$asked") "$PROVIDER" search "君の名は" >/dev/null 2>&1
  assert_contains "$(cat "$asked" 2>/dev/null)" "keyword=%E5%90%9B%E3%81%AE%E5%90%8D%E3%81%AF"
}

t_stream_refuses_an_embed_that_is_not_a_web_address() {
  local out
  if out=$(FAKE_SERVERS="$FIXTURES/servers-local-file.html" "$PROVIDER" stream frieren-beyond-journeys-end-481 1 sub best 2>&1); then
    fail "$current" "expected a non-zero exit"
  fi
  assert_contains "$out" "not a playable"
}

t_the_fetcher_speaks_only_http() {
  local reached="$WORK/reached" spy="$WORK/spy"
  printf '#!/bin/sh\ntouch %s\n' "$reached" >"$spy"
  chmod +x "$spy"
  local out
  out=$(OMANI_CURL="$spy" OMANI_BASE_API="file:///etc/hostname#" "$PROVIDER" search x 2>&1)
  assert_contains "$out" "not a web address"
  assert_missing "$reached"
}

t_stream_refuses_a_source_that_is_not_a_web_address() {
  local out
  if out=$(FAKE_SOURCES="$FIXTURES/sources-local-file.json" "$PROVIDER" stream frieren-beyond-journeys-end-481 1 sub best 2>&1); then
    fail "$current" "expected a non-zero exit"
  fi
  assert_contains "$out" "not a playable"
}

t_stream_refuses_a_mode_with_no_source() {
  local out
  out=$(FAKE_SERVERS="$FIXTURES/servers-sub-only.html" "$PROVIDER" stream frieren-beyond-journeys-end-481 1 dub best 2>&1)
  assert_contains "$out" "no dub source"
}

t_stream_reads_a_source_carried_inside_the_embed_page() {
  local out
  out=$(FAKE_SERVERS="$FIXTURES/servers-two.html" "$PROVIDER" stream frieren-beyond-journeys-end-481 1 sub best 2>&1)
  assert_contains "$out" "url	https://cdn/zoko/1080/i.m3u8"
  assert_contains "$out" "referrer	https://zokoanime.video/"
  assert_contains "$out" "subtitles	https://cdn/zoko/en.vtt"
}

t_stream_moves_on_when_a_server_gives_nothing() {
  local out
  out=$(FAKE_SERVERS="$FIXTURES/servers-two.html" \
    FAKE_ZOKO_PAGE="$FIXTURES/embed-zoko-empty.html" \
    "$PROVIDER" stream frieren-beyond-journeys-end-481 1 sub best 2>&1)
  assert_contains "$out" "url	https://cdn/1080/i.m3u8"
  assert_contains "$out" "referrer	https://megaplay.buzz/"
}

t_stream_names_the_server_that_answered() {
  local out
  out=$(FAKE_SERVERS="$FIXTURES/servers-two.html" "$PROVIDER" stream frieren-beyond-journeys-end-481 1 sub best 2>&1)
  assert_contains "$out" "server	ZokoAnime"
  assert_contains "$out" "skipped	0"
}

t_stream_counts_the_servers_that_refused_first() {
  local out
  out=$(FAKE_SERVERS="$FIXTURES/servers-two.html" \
    FAKE_ZOKO_PAGE="$FIXTURES/embed-zoko-empty.html" \
    "$PROVIDER" stream frieren-beyond-journeys-end-481 1 sub best 2>&1)
  assert_contains "$out" "server	Vidstream-2"
  assert_contains "$out" "skipped	1"
}

t_stream_tries_every_server_before_giving_up() {
  local log="$WORK/asked.txt" out
  : >"$log"
  if out=$(FAKE_URL_LOG="$log" FAKE_SERVERS="$FIXTURES/servers-two.html" \
    FAKE_ZOKO_PAGE="$FIXTURES/embed-zoko-empty.html" \
    FAKE_EMBED_PAGE="$FIXTURES/embed-zoko-empty.html" \
    "$PROVIDER" stream frieren-beyond-journeys-end-481 1 sub best 2>&1); then
    fail "$current" "expected a non-zero exit"
  fi
  assert_contains "$(cat "$log")" "zokoanime.video"
  assert_contains "$(cat "$log")" "megaplay.buzz"
  assert_contains "$out" "carried no source"
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
check "a server is found whatever order its attributes are in" t_a_server_is_found_whatever_order_its_attributes_are_in
check "a height does not carry to the next variant" t_a_height_does_not_carry_to_the_next_variant
check "one variant line is offered per declaration" t_one_variant_line_is_offered_per_declaration
check "the first matching server is the one used" t_the_first_matching_server_is_the_one_used
check "an embed hash that is not base64 is refused" t_an_embed_hash_that_is_not_base64_is_refused
check "a playlist that names no source is refused" t_a_playlist_that_names_no_source_is_refused
check "a subtitle that is not a web address is dropped" t_a_subtitle_that_is_not_a_web_address_is_dropped
check "a master playlist with no variants is refused" t_a_master_playlist_with_no_variants_is_refused
check "a cloudflare block on plain curl names the fix" t_a_cloudflare_block_on_plain_curl_names_the_fix
check "stream resolves through the source the site now serves" t_stream_resolves_through_the_source_the_site_now_serves
check "a server the site renames still plays" t_a_server_the_site_renames_still_plays
check "an embed carrying neither scheme is refused" t_an_embed_carrying_neither_scheme_is_refused
check "sources without an encrypted playlist are refused" t_sources_without_an_encrypted_playlist_are_refused
check "a playlist that will not decrypt is refused" t_a_playlist_that_will_not_decrypt_is_refused
check "usage names every subcommand" t_usage_names_every_subcommand
check "a query carrying url syntax is encoded" t_a_query_carrying_url_syntax_is_encoded
check "a query in another script is encoded as utf8" t_a_query_in_another_script_is_encoded_as_utf8
check "stream refuses an embed that is not a web address" t_stream_refuses_an_embed_that_is_not_a_web_address
check "the fetcher speaks only http" t_the_fetcher_speaks_only_http
check "stream refuses a source that is not a web address" t_stream_refuses_a_source_that_is_not_a_web_address
check "stream refuses a mode with no source" t_stream_refuses_a_mode_with_no_source
check "stream needs an id and an episode" t_stream_needs_an_id_and_an_episode
check "stream reads a source carried inside the embed page" t_stream_reads_a_source_carried_inside_the_embed_page
check "stream moves on when a server gives nothing" t_stream_moves_on_when_a_server_gives_nothing
check "stream tries every server before giving up" t_stream_tries_every_server_before_giving_up
check "stream names the server that answered" t_stream_names_the_server_that_answered
check "stream counts the servers that refused first" t_stream_counts_the_servers_that_refused_first

check "search rows come back as id and title" t_search_rows
check "search decodes html entities in titles" t_search_decodes_html_entities
check "search reads an anchor whatever else it carries" t_search_reads_an_anchor_whatever_else_it_carries
check "a title holding a tab stays one row" t_a_title_holding_a_tab_stays_one_row
check "episode rows do not depend on attribute order" t_episode_rows_do_not_depend_on_attribute_order
check "an id carrying a regex character matches itself" t_an_id_carrying_a_regex_character_matches_itself
check "a page that is not valid text is parsed without complaint" t_a_page_that_is_not_valid_text_is_parsed_without_complaint
check "search stops at the sidebar that repeats results" t_search_stops_at_the_sidebar
check "episode rows come back as id and number" t_episode_rows
check "episodes belonging to another series are ignored" t_episodes_ignore_another_series
check "qualities are sorted best first and made absolute" t_qualities_sorted_best_first
check "qualities survive tags between the variants" t_qualities_survive_tags_between_the_variants
check "a variant without a resolution is left out" t_a_variant_without_a_resolution_is_left_out
check "codecs carrying an x do not swallow the height" t_codecs_carrying_an_x_do_not_swallow_the_height
check "an already absolute variant url is left alone" t_qualities_keep_absolute_urls
check "i-frame variants are not offered as qualities" t_qualities_drop_iframe_variants
t_a_search_term_never_reaches_curls_arguments() {
  local seen="$WORK/argv-search"
  OMANI_CURL=$(argv_spy "$seen") "$PROVIDER" search "leak-probe-query" >/dev/null 2>&1
  if grep -q 'leak-probe-query' "$seen"; then
    fail "$current" "the term is in curl's argv, which every local account can read from /proc/<pid>/cmdline: $(cat "$seen")"
  fi
}

check "no subcommand prints usage and fails" t_usage_without_a_subcommand
check "a search term never reaches curl's arguments" t_a_search_term_never_reaches_curls_arguments

printf '\n%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
