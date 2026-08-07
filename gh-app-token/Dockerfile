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
# GHCR renders only the linked repository's ROOT readme on a package page and
# cannot be pointed at a subdirectory, so description is the only text a package
# page will carry for this builder. It is plain text, capped near 512 chars, and
# GHCR ignores the documentation annotation - that annotation is set anyway
# because it is the correct OCI field and tooling can read it from the manifest.
LABEL org.opencontainers.image.source="https://github.com/o8bit/cloud-builders"
LABEL org.opencontainers.image.documentation="https://github.com/o8bit/cloud-builders/blob/main/gh-app-token/readme.md"
LABEL org.opencontainers.image.description="Mints GitHub App installation access tokens and writes one file per account, so builds can reach private repositories under SAML SSO enforcement, which personal access tokens cannot. Takes no arguments; set GITHUB_APP_PRIVATE_KEY, GITHUB_APP_ID, GITHUB_APP_ORGS and GITHUB_APP_TOKEN_DIR. Writes <dir>/<account>.token at mode 0600 and never prints a token. Full docs: https://github.com/o8bit/cloud-builders/blob/main/gh-app-token/readme.md"

ENTRYPOINT ["/usr/local/bin/gh-app-token"]
