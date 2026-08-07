# cloud-builders

Custom build-step container images, published so consuming repositories do not
each carry their own copy of the same script.

One directory per builder, each published to `ghcr.io/o8bit/<name>` as a public
package — so any CI system, in any cloud project, or a laptop, can pull it with
no authentication.

## Builders

### [`gh-app-token`](gh-app-token/readme.md) → `ghcr.io/o8bit/gh-app-token`

Mints GitHub App **installation access tokens** and writes one file per account.
GitHub Apps are exempt from SAML SSO enforcement, which personal access tokens
and OAuth grants are not.

Takes no arguments — configured entirely by environment:

```sh
docker run --rm -v "$PWD/tokens:/tokens" \
  -e GITHUB_APP_PRIVATE_KEY="$(cat app.private-key.pem)" \
  -e GITHUB_APP_ID=123456 \
  -e GITHUB_APP_ORGS=YOUR_ORG \
  -e GITHUB_APP_TOKEN_DIR=/tokens \
  ghcr.io/o8bit/gh-app-token:sha-9a736de
```

**→ [Full documentation](gh-app-token/readme.md)** — environment reference,
output format, exit codes, permissions, and worked examples for Cloud Build, git
and Composer.

## If you arrived from a package page

GitHub Container Registry renders the linked repository's **root** README on a
package's landing page, and cannot be pointed at a subdirectory
([community discussion 151904](https://github.com/orgs/community/discussions/151904),
open since 2023, still unimplemented). The only other lever is
`org.opencontainers.image.description`, which is plain text capped around 512
characters
([discussion 26565](https://github.com/orgs/community/discussions/26565)).

So each builder's real documentation lives with the builder, and this page links
to it. Please don't "fix" that by moving a builder's docs up here — it only works
while there is one builder, and then breaks the next one.

## Adding a builder

Create a directory with a `Dockerfile`, a `readme.md`, and a workflow under
`.github/workflows/` that builds it, tests it and pushes to
`ghcr.io/o8bit/<name>`. Copy `gh-app-token` as a starting point, and add a
section above.

Two conventions worth keeping:

- **Test the built image, not the source tree.** Ship the test script inside the
  image and run it there in CI, so what you prove is what consumers pull.
- **Publish `sha-<short>` as well as `latest`.** Consumers pin the immutable tag.

Set `org.opencontainers.image.source` so GHCR links the package to this
repository — the publishing workflow's `GITHUB_TOKEN` depends on that link — and
`org.opencontainers.image.documentation` to the builder's readme URL. GHCR does
not render the latter, but it is the correct OCI annotation and tooling can read
it from the manifest.

New packages default to **private** visibility. Set them public after the first
publish, or nothing can pull them without credentials.
