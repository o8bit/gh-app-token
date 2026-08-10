# gh-app-token

A single POSIX sh script that mints GitHub App installation access tokens, plus its
test suite and the alpine image both ship in. `readme.md` is the user-facing
reference — read it before changing behaviour, and update it in the same commit.

This tool is consumed by builds in several repositories that pin `:1`. The
environment interface and the output layout are a published contract, not
internal detail.

## Invariants

Break any of these and the tool becomes unsafe or un-shareable. They are the
reason it looks the way it does.

**Never print a token.** Not on success, not in an error, not in a diagnostic,
not behind a debug flag. Errors name the *account* they concern, never the
credential. Composer's `github-oauth` validation is a live example of the damage:
it prints the rejected token into the build log, which is exactly why this repo
tells consumers to use `http-basic`.

**Create files, set their mode, then write.** Token files and the key file are
`: >file` then `chmod 600` then content — never the reverse, or the secret sits
world-readable for an instant. The token dir is `mkdir -p` + `chmod 700`.

**Mint only.** Do not add per-language output — no `auth.json`, no gitconfig, no
`GITHUB_TOKEN` export. Applying a token is the caller's job. This binds
`action.yml` too: it mints, masks, and reports a directory, and deliberately does
not configure git for you. Earlier versions
grew those outputs and were forked into every consuming repo as a result;
undoing that is the entire point of this repo existing. megameld's
`build/composer-auth.sh` is what an "apply" step looks like, and it lives there,
not here.

**POSIX sh, no bash.** Consumers run this in `php-fpm`, `phpunit` and alpine
containers that have no bash. It must pass under `sh`, `dash` and busybox.

**No new runtime dependencies.** The image has `ca-certificates curl jq openssl`
and nothing else. CI asserts that `git`, `php`, `composer` and `gh` are *absent*
— that assertion is deliberate, not leftover scaffolding. Adding a dependency
means every consumer pays for it.

**Don't pipe into the account loop.** A `while read` on the right of a pipe runs
in a subshell, where `ghat_fail`'s `exit` only leaves the subshell and the run
continues as if nothing failed. The loop is `for _name in "$@"` for that reason.

**Treat tokens as opaque.** GitHub is rolling between two installation-token
formats — a short opaque string, and a ~520-char `ghs_`-prefixed JWT with dots
and hyphens. No length assumption, no character-set regex, anywhere.

`GHAT_SKIP_MAIN=1` must keep working: the test suite sources the script to reach
individual functions, and only `ghat_main` is guarded.

## Tests

```sh
sh gh-app-token-test.sh                                  # 26 assertions, offline
docker run --rm --entrypoint sh ghcr.io/o8bit/gh-app-token:1 \
  /usr/local/bin/gh-app-token-test.sh                    # against a pulled image
```

Offline by design — no network, no credentials, no real App. Covers base64url
encoding, both accepted key forms, JWT construction and signature, account-list
parsing, output paths and file modes. Keep it that way: a test needing a real
private key is a test nobody runs.

Every behaviour change needs an assertion. Don't add one that can't fail —
asserting a value against itself passes forever and proves nothing.

## Releasing

Push a `vX.Y.Z` tag (via `gh release create`). That publishes docker tags
`X.Y.Z`, `X.Y`, `X` and `latest`, **and moves the `v<major>` git tag** that
composite-Action consumers pin to. Pushes to `main` and pull requests build and
test but publish nothing, so a release stays deliberate.

Testing and publishing are **separate jobs on purpose**. `test` runs on every
event and is read-only; `publish` runs only on a version tag and is the only job
holding `packages: write` and `contents: write`. Keep it that way — merging them
would hand a repo-writable token to every pull request run. `contents: write`
there is the workflow's own repo-scoped `GITHUB_TOKEN`, nothing to do with the
App's installation permissions, which must never gain `contents:write`.

Any change to an environment variable name, a default, or the output path is
**breaking** — new major, `2.0.0`, reachable as `:2`. Consumers pinned to `:1`
must not be moved onto it.

The tag validation in the workflow is verbose on purpose. Do not replace it with
a glob: `[0-9]*.[0-9]*.[0-9]*` looks like validation but `*` matches anything, so
`v1.0.0; rm -rf /` passes it.

## Distribution

Both the repo and the GHCR package are **public**. That matters because this tool
produces the credential builds need — requiring a credential to fetch it would be
circular — and because consumers span several orgs, so a public repo is also what
makes `uses: o8bit/gh-app-token@v1` resolve without an Actions access policy.

Consequences:

- The image is pulled, and the action resolved, anonymously by CI in other orgs.
  Don't add anything that assumes a GitHub login.
- **This is a public repo. Everything committed here is world-readable**, including
  comments naming consumer repositories and infrastructure. Nothing secret has
  ever been committed — the only key-shaped strings in history are a truncated
  dummy PEM and a fake `ghs_` literal in the test suite. Keep it that way: no real
  ids, hosts, or project names that would not be published deliberately.
- The `image.documentation` label now resolves for anonymous pullers, which it did
  not while the repo was private.

The repo is flattened to the root because GHCR renders only the linked repo's
root `readme.md` — there is no subdirectory support. Don't reintroduce a
`cloud-builders/gh-app-token/` style layout.

## Consumers

App id `4504876` (`OpenByte-CloudBuild`, enterprise-owned) across `fortifi/*` and
`chargehive/*`. Before changing anything in the contract above, grep the
consuming repos — `fortifi/megameld` alone has 27 Cloud Build configs and a
CircleCI job pointing at this image.

Two runner behaviours that constrain how it can be invoked:

- **CircleCI** ignores the image `ENTRYPOINT` for the primary container when the
  job declares `steps` and no `command`, so consumers must call
  `/usr/local/bin/gh-app-token` by path. Keep that path stable.
- **Cloud Build** gives each step a fresh container where only `/workspace`
  persists, so the token dir goes there — and is then readable by every later
  step in the build.

- **GitHub Actions** consumes `action.yml` at `o8bit/gh-app-token@v1`, which runs
  the script on the runner rather than pulling the image. That path needs the
  repo's Actions access policy set to `enterprise`, because this repo is private
  and the consumers sit in other orgs of the enterprise — check with
  `gh api repos/o8bit/gh-app-token/actions/permissions/access`. It also needs the
  moving `v1` git tag, which the publish job maintains.

  `actions/create-github-app-token` is the simpler choice for a single org and is
  worth recommending there. It mints per owner, so a workflow needing three orgs
  needs three invocations — that is the case this action exists for.
