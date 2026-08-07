FROM alpine:3

# openssl signs the App JWT, curl calls the API, jq reads the responses.
# ca-certificates is needed for TLS to api.github.com.
# Deliberately no git, no php, no gh: this image mints tokens and nothing else.
RUN apk add --no-cache ca-certificates curl jq openssl

COPY gh-app-token /usr/local/bin/gh-app-token
COPY gh-app-token-test.sh /usr/local/bin/gh-app-token-test.sh
RUN chmod +x /usr/local/bin/gh-app-token /usr/local/bin/gh-app-token-test.sh

# source lets GHCR associate the package with this repo, which the publishing
# workflow's GITHUB_TOKEN relies on.
#
# GHCR renders the linked repository's root readme on the package page, which is
# why this builder has a repository to itself rather than living in a monorepo
# subdirectory - GHCR cannot be pointed at one. description supplements that with
# a one-liner; GHCR ignores the documentation annotation, but it is the correct
# OCI field and tooling can read it from the manifest.
LABEL org.opencontainers.image.source="https://github.com/o8bit/gh-app-token"
LABEL org.opencontainers.image.documentation="https://github.com/o8bit/gh-app-token/blob/main/readme.md"
LABEL org.opencontainers.image.description="Mints GitHub App installation access tokens and writes one file per account, so builds can reach private repositories under SAML SSO enforcement, which personal access tokens cannot. Takes no arguments; configured entirely by environment. See the README for the full reference."

ENTRYPOINT ["/usr/local/bin/gh-app-token"]
