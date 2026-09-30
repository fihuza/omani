# Contributing to Omani

Thanks for taking the time. This page says what the automation will accept, so
you find out here rather than from a rejected push.

## Getting set up

```bash
git clone https://github.com/fihuza/omani.git
cd omani
git config core.hooksPath scripts
mise install
```

`mise` pins the toolchain — Node, eslint and git-cliff — so your run matches
CI's. The `toolchain` gate refuses to run against anything else.

The rest comes from Arch:

```bash
omarchy pkg add qt6-declarative shellcheck shfmt jq
```

The test suites reach no network and start no player. They pass on a machine
with none of the plugin's runtime dependencies installed.

## Branch names

New branches must start with one of these. **Anything else is rejected when the
branch is created**, not when you open the pull request:

| Prefix | For |
|---|---|
| `feature/` | new work |
| `fix/` | fixing something that is broken |
| `release/` | a version bump on the way to `main` |
| `hotfix/` | an urgent fix cut from `main` |

`main` and `develop` are protected: no direct pushes, no force pushes, no
deletions. Everything reaches them through a pull request.

Branch from `develop` unless you are cutting a release or a hotfix, which come
from `main`.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org). The `commit-msg`
hook and the `Commit messages` check both enforce this, so a message that
passes locally passes in CI:

```
<type>(<optional scope>)!: <description>
```

- **type** is one of `feat`, `fix`, `refactor`, `perf`, `test`, `docs`,
  `chore`, `style`, `ci`, `build`, `revert`
- **scope** is optional, lowercase, letters, digits and hyphens
- **description** is entirely lowercase and starts the line after `: `
- the whole first line is at most **100 characters**

```
fix: try every server the site lists before giving up
test(model): pin the boundaries the operators could not reach
```

Say what changed and why. A reader should not need anything but the repository
to follow it.

## Pull requests

Merged with a **merge commit**, never a squash. A squashed back-merge leaves
`develop` carrying `main`'s changes without `main` among its ancestors, and
every later release then conflicts on `manifest.json`.

Two checks must pass before a pull request can merge: **Quality** and **Commit
messages**.

Only `release/*` and `hotfix/*` may merge into `main`, and only those may
change the version in `manifest.json`.

## Before you push

```bash
./scripts/pre-commit
```

That is the same script CI runs, in the same order, so a green run locally is a
green pipeline. It runs eleven gates:

```
toolchain    qml-format   qml-lint    shell-format   shell-lint
js-lint      manifest     unit        qml-tests      shell-tests    version
```

**Every gate fails on a warning, not only on an error.** A warning nobody has
to act on is one everybody stops reading.

Run one by name — `./scripts/pre-commit qml-lint`. A name that is not a gate is
refused rather than reported as passing.

## Tests

Four runners, no framework and no npm dependencies:

| What | Run by |
|---|---|
| `Model.js` | `node --test`, with coverage at 90% or better |
| `Panel.qml`, `Service.qml`, `BarWidget.qml`, `AnimeIcon.qml` | `qmltestrunner` against stubs |
| `bin/omani`, `bin/omani-provider` | plain bash |
| the gates themselves | plain bash |

**When you fix a bug, write the test that reproduces it first**, watch it fail,
then fix it. A test that passes before the fix is testing something else.

Name a test for the behaviour rather than the function: `resumes from the stored
episode`, not `test_resumeEpisode_1`.

`scripts/mutate` changes the code and reports what no test noticed. It drives
three tools, one per layer:

| Layer | Tool | Run it |
|---|---|---|
| `Model.js` | [StrykerJS](https://stryker-mutator.io) | `./scripts/mutate model` |
| `*.qml` | [qmutant](https://github.com/fihuza/qmutant) | `./scripts/mutate qml` |
| `bin/omani*` | every refusal deleted in turn | `./scripts/mutate shell` |

Both mutation tools come from `mise`, so they need no setup beyond
`mise install`. The pipeline runs the first two on every pull request into
`main`; run them before proposing a release.

## Never silence a finding

A gate exists to surface problems. When one fails there are three honest
answers: fix the finding, fix the code it is complaining about, or report it and
stop. Never add an ignore flag, lower a threshold, or weaken an assertion to
make a gate pass.

A verified false positive is the exception, and it is recorded in the open — a
directive on the line itself, carrying its reason, so it comes back the moment
that code changes.

## Reporting something

Open an issue with what you did, what happened, and what you expected. If a
video failed to play, the output of `bin/omani-provider stream <anime-id>
<episode>` says a great deal.

Security problems go through `SECURITY.md` instead, privately.

## Licence

GPL-3.0-or-later, because `bin/omani-provider` is derived from ani-cli. By
contributing you agree your work ships under it. Before copying code from
another project, check that its licence allows this.
