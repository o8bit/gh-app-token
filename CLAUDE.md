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
`GITHUB_TOKEN` export. Applying a token is the caller's job. Earlier versions
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

Push a `vX.Y.Z` tag (via `gh release create`). That publishes `X.Y.Z`, `X.Y`,
`X` and `latest`. Pushes to `main` and pull requests build and test but publish
nothing, so a release stays deliberate.

Any change to an environment variable name, a default, or the output path is
**breaking** — new major, `2.0.0`, reachable as `:2`. Consumers pinned to `:1`
must not be moved onto it.

The tag validation in the workflow is verbose on purpose. Do not replace it with
a glob: `[0-9]*.[0-9]*.[0-9]*` looks like validation but `*` matches anything, so
`v1.0.0; rm -rf /` passes it.

## Distribution

The repo is **private**; the GHCR package is **public**. Org settings disable
public and internal repo visibility, and package visibility is configured
separately. A public package matters because this tool produces the credential
builds need — requiring a credential to fetch it would be circular.

Two consequences:

- The image is pulled anonymously by CI in other orgs. Don't add anything that
  assumes a GitHub login.
- Anonymous pullers **cannot** read this repo, so the `image.documentation`
  label and the "see the README" text in `image.description` point somewhere
  they can't reach. Worth fixing by moving the reference documentation into the
  labels or a public location; don't add more pointers to it meanwhile.

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

GitHub Actions should use `actions/create-github-app-token` instead of this.
