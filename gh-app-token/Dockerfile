FROM alpine:3

# openssl signs the App JWT, curl calls the API, jq reads the responses.
# ca-certificates is needed for TLS to api.github.com.
# Deliberately no git, no php, no gh: this image mints tokens and nothing else.
RUN apk add --no-cache ca-certificates curl jq openssl

COPY gh-app-token /usr/local/bin/gh-app-token
COPY gh-app-token-test.sh /usr/local/bin/gh-app-token-test.sh
RUN chmod +x /usr/local/bin/gh-app-token /usr/local/bin/gh-app-token-test.sh

# Lets GHCR associate the package with this repo, which the publishing
# workflow's GITHUB_TOKEN relies on.
LABEL org.opencontainers.image.source="https://github.com/o8bit/cloud-builders"
LABEL org.opencontainers.image.description="Mints GitHub App installation tokens for named orgs"

ENTRYPOINT ["/usr/local/bin/gh-app-token"]
