# gh-app-token

Mints GitHub App **installation access tokens** and writes one file per account.

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

The image is public — no authentication is needed to pull it. That is
deliberate: this tool produces GitHub credentials, so it must not require one to
fetch.

## Usage

**The image takes no arguments.** Everything is configured by environment
variables, and the entrypoint is the tool itself, so a bare `docker run` is the
whole invocation:

```sh
docker run --rm \
  -v "$PWD/tokens:/tokens" \
  -e GITHUB_APP_PRIVATE_KEY="$(cat app.private-key.pem)" \
  -e GITHUB_APP_ID=123456 \
  -e GITHUB_APP_ORGS=YOUR_ORG \
  -e GITHUB_APP_TOKEN_DIR=/tokens \
  ghcr.io/o8bit/gh-app-token:sha-ecbac13
```

That writes `./tokens/YOUR_ORG.token`.

### Environment

| Variable | Required | Meaning |
|---|---|---|
| `GITHUB_APP_PRIVATE_KEY` | yes | The App private key, as a raw PEM **or** base64-encoded PEM |
| `GITHUB_APP_ID` | yes | The App's id. Not a secret |
| `GITHUB_APP_ORGS` | yes | Comma-separated account names, e.g. `org-a,org-b`. Whitespace after commas is fine |
| `GITHUB_APP_TOKEN_DIR` | yes | Directory for the token files. Created at mode `0700` if absent |
| `GITHUB_APP_PERMISSIONS` | no | JSON permission set to request. Default `{"contents":"read"}` |

Base64 is accepted for the key because some CI systems mangle multi-line
variable values. Either form works; the tool detects which it was given.

### Output

One file per account, at `$GITHUB_APP_TOKEN_DIR/<account>.token`, mode `0600`,
containing only the token. Files are created and permission-set *before* the
token is written, so they are never briefly world-readable with a secret in them.

On success it prints one line per account to stdout:

```
gh-app-token: YOUR_ORG: installation 12345678, expires 2026-08-07T12:34:56Z, token written to /tokens/YOUR_ORG.token
```

**The token itself is never printed** — not on success, not in any error, not in
any diagnostic. Don't add one.

### Exit behaviour

Exits `0` on success, `1` on any failure, `130` if interrupted. Every failure
prints a `gh-app-token:` prefixed message to stderr naming the account it
concerns. Failures stop the run immediately — if the first of three accounts
fails, the other two are not minted.

Common ones:

| Message | Cause |
|---|---|
| `... is not a valid RSA private key` | key missing, truncated, or not RSA |
| `app N is not installed on 'X' (tried both org and user)` | the App isn't installed on that account |
| `token mint for 'X' failed (HTTP 422)` | you asked for a permission the installation doesn't grant |
| `the installation for 'X' has no accessible repositories` | installed, but with access to nothing |

## Before it will work

The App must be **installed on every account** you name in `GITHUB_APP_ORGS`,
and must be granted the permissions you request. Installation is per account: an
App installs at most once per org or user, so the account name identifies the
installation unambiguously.

You do not supply installation ids. The tool resolves each name via
`GET /orgs/{name}/installation`, falling back to `GET /users/{name}/installation`
so Apps installed on personal accounts work too. Names are used rather than ids
because reinstalling an App changes its installation id but not the account name
— ids silently break every consumer, names don't.

### Permissions

`GITHUB_APP_PERMISSIONS` narrows the minted token to the subset you actually
need, and applies to every account in the list:

```sh
-e GITHUB_APP_PERMISSIONS='{"contents":"read"}'                      # default
-e GITHUB_APP_PERMISSIONS='{"contents":"read","pull_requests":"read"}'
-e GITHUB_APP_PERMISSIONS='{"actions":"write"}'                       # dispatch a workflow
```

You can only narrow, never widen. Requesting a permission the installation was
not granted fails with HTTP 422 — it does not quietly return a lesser token. If
you need different permissions per account, run the tool twice.

### Several accounts at once

A token is scoped to one installation, so private repositories in three orgs
need three tokens:

```sh
-e GITHUB_APP_ORGS='org-a,org-b,org-c'
```

writes `org-a.token`, `org-b.token` and `org-c.token`.

## Google Cloud Build

```yaml
availableSecrets:
  secretManager:
    - versionName: projects/YOUR_PROJECT/secrets/YOUR_SECRET/versions/latest
      env: 'GITHUB_APP_PRIVATE_KEY'

steps:
  - id: 'gh-token'
    name: 'ghcr.io/o8bit/gh-app-token:sha-ecbac13'
    env:
      - 'GITHUB_APP_ID=123456'
      - 'GITHUB_APP_ORGS=YOUR_ORG'
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

Don't use this. Actions has
[`actions/create-github-app-token`](https://github.com/actions/create-github-app-token)
built in, which does the same job with less ceremony.

## Using the token

### git, and anything built on it (Go modules, submodules)

Rewrite per account — several accounts can coexist:

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

Use `http-basic`, **not** `github-oauth`:

```json
{"http-basic":{"github.com":{"username":"x-access-token","password":"TOKEN"}}}
```

Composer validates `github-oauth` values against `{^[.A-Za-z0-9_]+$}`, which
rejects hyphens — and installation tokens contain them. Worse, the exception
prints the rejected token into the build log. `http-basic` has no such
validation and works on every Composer version.

Composer holds one credential per host, so `auth.json` can serve only **one**
account. A project with private dependencies in several orgs needs its git
`insteadOf` rules to do the work instead.

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
docker run --rm --entrypoint sh ghcr.io/o8bit/gh-app-token:sha-ecbac13 \
  /usr/local/bin/gh-app-token-test.sh
```

It is offline — no network, no credentials — and covers base64url encoding, key
handling in both accepted forms, JWT construction and signature, account-list
parsing and output paths.

## Image tags

| Tag | |
|---|---|
| `sha-<short>` | immutable, built from that commit. **Pin this.** |
| `latest` | moves with `main` |
