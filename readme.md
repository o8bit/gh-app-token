# gh-app-token

Mints GitHub App **installation access tokens**, limited to the repositories you
name, and writes one file per owner.

It does that and nothing else. It does not configure git, Composer, Go modules or
anything else — the caller applies the token wherever it needs it. Earlier
versions of this script grew per-language outputs and were forked as a result.

Why an App token rather than a personal access token: GitHub Apps are exempt from
SAML SSO enforcement, while personal access tokens, OAuth grants and user SSH
keys are not. Under an enterprise with SAML enforced, a PAT stops working the
moment its SSO authorisation lapses, and takes every build with it.

```
ghcr.io/o8bit/gh-app-token
```

The image and this repository are both public — no authentication is needed to
pull the image or to use the action. That is deliberate: this tool produces
GitHub credentials, so it must not require one to fetch.

## Usage

**The image takes no arguments.** Everything is configured by environment
variables, and the entrypoint is the tool itself, so a bare `docker run` is the
whole invocation:

```sh
docker run --rm \
  -v "$PWD/tokens:/tokens" \
  -e GITHUB_APP_PRIVATE_KEY="$(cat app.private-key.pem)" \
  -e GITHUB_APP_ID=123456 \
  -e GITHUB_APP_REPOSITORIES=YOUR_ORG/YOUR_REPO \
  -e GITHUB_APP_TOKEN_DIR=/tokens \
  ghcr.io/o8bit/gh-app-token:2
```

That writes `./tokens/YOUR_ORG.token`, which can reach `YOUR_ORG/YOUR_REPO` and
nothing else.

### Environment

| Variable | Required | Meaning |
|---|---|---|
| `GITHUB_APP_PRIVATE_KEY` | yes | The App private key, as a raw PEM **or** base64-encoded PEM |
| `GITHUB_APP_ID` | yes | The App's id. Not a secret |
| `GITHUB_APP_REPOSITORIES` | yes | Comma-separated `owner/repo` entries, e.g. `org-a/lib,org-b/sdk`. `owner/*` for every repository the installation covers. Whitespace after commas is fine |
| `GITHUB_APP_TOKEN_DIR` | yes | Directory for the token files. Created at mode `0700` if absent |
| `GITHUB_APP_PERMISSIONS` | no | JSON permission object to request. Default `{"contents":"read"}` |

Base64 is accepted for the key because some CI systems mangle multi-line
variable values. Either form works; the tool detects which it was given.

### Output

One file per owner, at `$GITHUB_APP_TOKEN_DIR/<owner>.token`, mode `0600`,
containing only the token. Files are created and permission-set *before* the
token is written, so they are never briefly world-readable with a secret in them.

On success it prints one line per owner to stdout, naming the repositories its
token reaches:

```
gh-app-token: YOUR_ORG: installation 12345678, YOUR_REPO, expires 2026-08-07T12:34:56Z, token written to /tokens/YOUR_ORG.token
```

**The token itself is never printed** — not on success, not in any error, not in
any diagnostic. Don't add one.

### Exit behaviour

Exits `0` on success, `1` on any failure, `130` if interrupted. Every failure
prints a `gh-app-token:` prefixed message to stderr naming the owner or entry it
concerns. Failures stop the run immediately — if the first of three owners
fails, the other two are not minted. The repository list is validated before
anything is minted.

Common ones:

| Message | Cause |
|---|---|
| `... is not a valid RSA private key` | key missing, truncated, or not RSA |
| `GITHUB_APP_ORGS was replaced by GITHUB_APP_REPOSITORIES in v2` | a v1 configuration; see [Upgrading from v1](#upgrading-from-v1) |
| `'X' is not owner/repo` | an entry without exactly one `/`, or with an empty side |
| `'X/*' cannot be combined with named repositories of 'X'` | the list reads narrower than the token it would mint; keep one or the other |
| `app N is not installed on 'X' (tried both org and user)` | the App isn't installed on that account |
| `token mint for 'X' failed (HTTP 422)` | a permission the installation doesn't grant, or a repository that doesn't exist or the installation doesn't cover |
| `the installation for 'X' has no accessible repositories` | installed, but with access to nothing |

## Before it will work

The App must be **installed on every owner** in `GITHUB_APP_REPOSITORIES`,
and must be granted the permissions you request. Installation is per account: an
App installs at most once per org or user, so the account name identifies the
installation unambiguously.

You do not supply installation ids. The tool resolves each name via
`GET /orgs/{name}/installation`, falling back to `GET /users/{name}/installation`
so Apps installed on personal accounts work too. Names are used rather than ids
because reinstalling an App changes its installation id but not the account name
— ids silently break every consumer, names don't.

### Permissions

`GITHUB_APP_PERMISSIONS` narrows *what* the minted token can do, and applies to
every owner in the list:

```sh
-e GITHUB_APP_PERMISSIONS='{"contents":"read"}'                      # default
-e GITHUB_APP_PERMISSIONS='{"contents":"read","pull_requests":"read"}'
-e GITHUB_APP_PERMISSIONS='{"actions":"write"}'                       # dispatch a workflow
```

You can only narrow, never widen. Requesting a permission the installation was
not granted fails with HTTP 422 — it does not quietly return a lesser token. If
you need different permissions per owner, run the tool twice.

### Repositories

`GITHUB_APP_REPOSITORIES` narrows *where* the token works. Without it, an
installation token reaches every repository the installation covers — often a
whole org — when a build usually needs two or three. Name exactly those:

```sh
-e GITHUB_APP_REPOSITORIES='org-a/lib,org-a/app,org-b/sdk'
```

writes `org-a.token`, reaching `lib` and `app`, and `org-b.token`, reaching
`sdk`. A token belongs to one installation, so each owner gets its own; the
owners are read from the entries, in the order they first appear.

`owner/*` mints for every repository the installation covers. It exists for the
job that genuinely needs a whole org, and makes that scope something written in
the configuration rather than a default. It cannot be combined with named
repositories of the same owner.

GitHub rejects a repository that does not exist or that the installation does
not cover (HTTP 422), so a typo fails the mint rather than producing a token
that 404s later. For dependency fetches, the list is usually the private
modules in the project's manifest (`go.mod`, `composer.json`, `package.json`).

### Upgrading from v1

v1 took `GITHUB_APP_ORGS` (action input `orgs`) and minted every token for the
whole installation. v2 replaces it with `GITHUB_APP_REPOSITORIES` (action input
`repositories`); setting the old variable fails rather than being ignored.
The output layout — `<owner>.token` in the token directory — is unchanged, so
whatever applies the token needs no change.

| v1 | v2, scoped | v2, same scope as v1 |
|---|---|---|
| `GITHUB_APP_ORGS=org-a,org-b` | `GITHUB_APP_REPOSITORIES=org-a/lib,org-b/sdk` | `GITHUB_APP_REPOSITORIES=org-a/*,org-b/*` |

The `:1` image and the `v1` git tag stay where they are; nothing moves onto v2
until its configuration does.

## Google Cloud Build

```yaml
availableSecrets:
  secretManager:
    - versionName: projects/YOUR_PROJECT/secrets/YOUR_SECRET/versions/latest
      env: 'GITHUB_APP_PRIVATE_KEY'

steps:
  - id: 'gh-token'
    name: 'ghcr.io/o8bit/gh-app-token:2'
    env:
      - 'GITHUB_APP_ID=123456'
      - 'GITHUB_APP_REPOSITORIES=YOUR_ORG/YOUR_REPO'
      - 'GITHUB_APP_TOKEN_DIR=/workspace/.gh-tokens'
    secretEnv: [ 'GITHUB_APP_PRIVATE_KEY' ]
    waitFor: [ '-' ]
```

Then consume it in a later step. **Note the `$$`** — Cloud Build runs its own
substitution pass before the shell, so a single `$` is consumed there and you
would silently get an empty value:

```yaml
  - id: 'use-it'
    name: 'alpine'
    entrypoint: 'sh'
    args:
      - '-c'
      - |
        GITHUB_TOKEN="$$(cat /workspace/.gh-tokens/YOUR_ORG.token)"
        export GITHUB_TOKEN
        # ...
```

Each Cloud Build step is a fresh container and only `/workspace` persists
between them, which is why the token directory goes there. The corollary: a
token in `/workspace` is readable by **every later step in the build**. Where a
token is only needed inside one step, mint it in that step and write it
somewhere that does not outlive it.

## GitHub Actions

Use it as a composite action rather than the image:

```yaml
- uses: o8bit/gh-app-token@v2
  id: gh-token
  with:
    app-id: ${{ secrets.APP_ID }}
    private-key: ${{ secrets.APP_PRIVATE_KEY }}
    repositories: org-a/lib,org-b/sdk

- name: Fetch private modules
  env:
    TOKEN_DIR: ${{ steps.gh-token.outputs.token-dir }}
  run: |
    git config --global \
      "url.https://x-access-token:$(cat "$TOKEN_DIR/org-a.token")@github.com/org-a/.insteadOf" \
      "https://github.com/org-a/"
```

`app-id` takes the App's id **or** its client id — the value is only the JWT
issuer, and GitHub accepts either. `permissions` and `token-dir` are optional;
`token-dir` defaults to a directory under `RUNNER_TEMP`, outside the workspace.

The action runs the script directly rather than pulling the image. Runners
already have `curl`, `jq`, `openssl` and `base64`, so there is nothing to
install, nothing to pull, and no container writing root-owned `0600` files that
the runner user then cannot read.

**Every minted token is masked** with `::add-mask::` before the action returns.
Action outputs are masked for you; a token read out of a file is not.

[`actions/create-github-app-token`](https://github.com/actions/create-github-app-token)
is the obvious alternative, and is simpler if you need one org. It mints per
owner, so three orgs means three invocations and three separate rewrites — that
case is what this action is for.

The same repository list scopes every token, so a job that needs one library
from another org receives a token for that library, not for the org.

## Using the token

Applying a token is the caller's job — this tool only mints. Which method you
want depends on how many accounts you need and what is consuming the token.

| Consumer | One account | Several accounts |
|---|---|---|
| git, Go modules, submodules | `.netrc` | `insteadOf` per account |
| npm, dependency from a git URL | `.netrc` | `insteadOf` per account |
| Composer | `auth.json` `http-basic` | `auth.json` **plus** git `insteadOf` |
| npm, package from GitHub Packages | `.npmrc` `_authToken` | one token per registry host |

The split is not per tool, it is per fetch path. Anything that resolves through
git — Go modules, npm dependencies given as `github:org/repo` or a `git+https`
URL, submodules — inherits whatever git is configured with and needs no
mechanism of its own. Anything with its own registry client — Composer, or npm
against GitHub Packages — authenticates from its own file and ignores git's
configuration entirely.

### git and Go — one account: .netrc

Keeps the token out of git config entirely, so it cannot reach a log through
`git config --list`, a printed remote, or a gitconfig kept as a build artefact:

```sh
: >~/.netrc && chmod 600 ~/.netrc          # create and restrict, then write
printf 'machine github.com login x-access-token password %s\n' \
  "$(cat /tokens/org-a.token)" >~/.netrc
```

Write it, do not append: a second `>>` leaves two `machine github.com` lines and
the **stale one wins**, so a build silently keeps using an expired token.

If your manifests use `git@github.com:` URLs, you still need a rewrite — but it
carries no secret, so it is safe to log:

```sh
git config --global url."https://github.com/org-a/".insteadOf "git@github.com:org-a/"
```

### git and Go — several accounts: insteadOf

`.netrc` matches on **host**, and every account is `github.com`, so it can hold
only one token. Installation tokens are per account, so anything spanning
accounts has to use a rewrite:

```sh
for org in org-a org-b; do
  git config --global \
    "url.https://x-access-token:$(cat /tokens/$org.token)@github.com/$org/.insteadOf" \
    "https://github.com/$org/"
done
```

Use `x-access-token:<token>`. GitHub **rejects** `<token>:x-oauth-basic` for
installation tokens with "Password authentication is not supported for Git
operations" — which matters because that is the form some tools build
internally.

### Composer

Composer does **not** read `.netrc`. Its HTTP client authenticates from
`auth.json` (or `COMPOSER_AUTH`) only, so netrc is not an option here even for a
single account — without `auth.json` Composer hits the GitHub API
unauthenticated and falls back to cloning.

Use `http-basic`, **not** `github-oauth`:

```json
{"http-basic":{"github.com":{"username":"x-access-token","password":"TOKEN"}}}
```

Composer validates `github-oauth` values against `{^[.A-Za-z0-9_]+$}`, which
rejects hyphens — and installation tokens contain them. Worse, the exception
prints the rejected token into the build log. `http-basic` has no such
validation and works on every Composer version.

`auth.json` also holds one credential per host, so it serves one account. A
project with private dependencies in several accounts needs git `insteadOf`
rules alongside it.

### What none of these fix

Whichever method you pick, the token is an argument to the command that writes
it. Any shell tracing — `set -x`, or a CI that echoes commands before running
them — prints that command, token included. Turn tracing off around the step
rather than assuming the method protects you.

`curl` does not read `.netrc` unless you pass `--netrc`, so API calls need the
token given to them explicitly. `gh` reads `GITHUB_TOKEN` from the environment
and ignores both methods.

## Treat tokens as opaque

Do not assume a token's length, character set or structure anywhere — not in a
validation regex, not in a log-scrubbing pattern, not in a database column
width.

GitHub issues installation tokens in two forms and is
[rolling between them](https://github.blog/changelog/2026-05-15-github-app-installation-tokens-per-request-override-header/):
a short opaque string with no dots, and a longer `ghs_`-prefixed JWT of ~520
characters containing dots and often hyphens. Which one you get can vary between
calls. GitHub's own recommended matcher is `ghs_[A-Za-z0-9\.\-_]{36,}`.

Tokens expire one hour after minting.

## Tests

```sh
sh gh-app-token-test.sh
```

The suite ships inside the image, so you can run it against the exact artefact
you pull:

```sh
docker run --rm --entrypoint sh ghcr.io/o8bit/gh-app-token:2 \
  /usr/local/bin/gh-app-token-test.sh
```

It is offline — no network, no credentials — and covers base64url encoding, key
handling in both accepted forms, JWT construction and signature, repository-list
parsing and validation, the mint request body, and output paths.

## Image tags

Releases are semver, cut by pushing a `vX.Y.Z` git tag. Each release publishes
four tags:

| Tag | Moves? | Use when |
|---|---|---|
| `1.2.3` | never | you want the exact image, forever |
| `1.2` | picks up patches | **the usual choice** |
| `1` | picks up features and patches, never breaking changes | you want fixes without touching config |
| `latest` | anything, including breaking changes | never, in a build |

Breaking changes to the environment interface or output layout go in a new
major: `2.0.0`, reachable as `:2`. A consumer pinned to `:1` will not be moved
onto it.

Pushes to `main` and pull requests build and test but publish nothing, so a
release stays a deliberate act. Testing and publishing are separate jobs: only
the publish job, which runs on a version tag, holds the credentials that can push
an image or move a tag.

A release also **moves the `v<major>` git tag**, because composite-Action
consumers pin a git ref (`@v1`) rather than a docker tag. Docker `1.2.3` and git
`v1.2.3` are immutable; docker `1`, `1.2`, `latest` and git `v1` all move.
