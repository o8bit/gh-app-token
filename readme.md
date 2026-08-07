# cloud-builders

Custom build-step container images, published so that consuming repositories do
not each carry their own copy of the same script.

One directory per builder. Each publishes to `ghcr.io/o8bit/<name>` as a public
package, so any CI system — in any cloud project, or on a laptop — can pull it
with no authentication.

| Builder | Purpose |
|---|---|
| [`gh-app-token`](gh-app-token/readme.md) | Mints GitHub App installation tokens for named accounts |

## Adding a builder

Create a directory containing a `Dockerfile` and a `readme.md`, and a workflow
under `.github/workflows/` that builds it, tests it, and pushes to
`ghcr.io/o8bit/<name>`. Copy `gh-app-token` as a starting point.

Two conventions worth keeping:

- **Test the built image, not the source tree.** Ship the test script inside the
  image and run it there in CI, so what you prove is what consumers pull.
- **Publish `sha-<short>` as well as `latest`.** Consumers pin the immutable tag;
  `latest` exists for convenience.

New packages default to **private** visibility. Set them public after the first
publish, or nothing can pull them without credentials.
