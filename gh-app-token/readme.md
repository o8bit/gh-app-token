# gh-app-token

**The documentation for this builder is the [repository root README](../readme.md).**

It lives there rather than here because GitHub Container Registry renders a
package's linked repository root README on the package landing page, and cannot
be pointed at a subdirectory — so anyone arriving from
`ghcr.io/o8bit/gh-app-token` would otherwise find no instructions.

Edit the root README, not this file.

This directory holds the builder itself:

| File | |
|---|---|
| `gh-app-token` | the script |
| `gh-app-token-test.sh` | offline assertion tests, also shipped inside the image |
| `Dockerfile` | Alpine plus openssl, curl and jq |
