# Security

## Reporting a vulnerability

Report it privately through
[GitHub's advisory form](https://github.com/fihuza/omani/security/advisories/new).
Please do not open a public issue for something exploitable.

Expect a first reply within a week. If a fix is warranted it ships as a
`hotfix/*` release, and the advisory is published once users have had a
version to update to.

## Why this plugin warrants a policy

Omani runs **unsandboxed inside the shared `omarchy-shell` process**, with the
full permissions of the user running it. It is not a sandboxed app: a flaw
here reaches the whole desktop session, not one window.

It also reads from a site it does not control. The search results, the episode
list, the stream url, the subtitle url and the obfuscated embed payload all
arrive from the provider, and they end up in the argv of a media player and in
the arguments of `curl`. That is the boundary most worth attacking, and it is
guarded deliberately:

- a url that is not `http` or `https` is refused, by the provider and again by
  the player's caller
- `mpv` is given `--` before the url, so an answer beginning with a dash cannot
  become an option
- `curl` is confined to `http` and `https` on the request and on every redirect
  it follows, so a `file://` embed cannot be fetched
- everything the user types is percent-encoded with shell builtins before it
  becomes part of a url

If you find a way past any of those, that is the report worth sending.

## In scope

- Anything that turns provider output into command execution, file access or
  an argument the player or `curl` was not meant to receive
- Anything that writes outside the watch history and the player list, or
  corrupts them in a way the user cannot recover from
- Anything that leaks the user's watch history or system information off the
  machine

## Out of scope

- The provider's own site, availability or content
- `mpv`, `curl`, `jq` and the rest of the base system
- Omarchy and Quickshell themselves, which have their own projects
- Watching anime being against a site's terms of service, which is a question
  for the user and not a vulnerability

## Supported versions

The latest release, which is what `omarchy plugin update` serves. Fixes are
not backported.
