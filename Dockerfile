# DevDocs for Railway. Upstream publishes no releases and its GHCR image has not
# been rebuilt since 2026-02-01, so this builds the app from a pinned upstream
# commit on the official Ruby image that upstream's Gemfile requires.
FROM ruby:4.0.9-slim@sha256:d8cb2c0714bdaba0f318af897a01d2dbde3cfa8e62d47e99cea55feb13c0e90d

ARG DEVDOCS_COMMIT=e6ee9b5673346e73962e037146de2b4f5109ae0f

ENV LANG=C.UTF-8 \
    RACK_ENV=production \
    NEW_RELIC_AGENT_ENABLED=false \
    BUNDLE_WITHOUT="development:test"

WORKDIR /devdocs

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates git build-essential nodejs libcurl4t64 libarchive-tools webp; \
    git init -q .; \
    git fetch -q --depth 1 https://github.com/freeCodeCamp/devdocs.git "$DEVDOCS_COMMIT"; \
    git checkout -q FETCH_HEAD; \
    rm -r .git test; \
    gem install bundler --no-document; \
    bundle config set path.system true; \
    bundle install --jobs 2; \
    apt-get purge -y --auto-remove git build-essential; \
    rm -r /var/lib/apt/lists/* /root/.bundle/cache /usr/local/bundle/cache || true

# Self-hosting patches, each checked so a version bump that moves the code fails the build:
# 1. /ping answers over plain HTTP so Railway's health check isn't redirected to HTTPS.
# 2. Documents are served from this server (/docs), not from devdocs.io's CDN.
# 3. The browser app runs as "selfhosted": no devdocs.io-only location warning, no analytics.
RUN set -eux; \
    sed -i "s|unless request.scheme == 'https'|unless request.scheme == 'https' \|\| request.path == '/ping'|" lib/app.rb; \
    grep -q "request.path == '/ping'" lib/app.rb; \
    sed -i "\|set :docs_origin, '//documents.devdocs.io'|d" lib/app.rb; \
    ! grep -q "documents.devdocs.io'" lib/app.rb; \
    sed -i "s|env: '<%= App.environment %>',|env: 'selfhosted',|" assets/javascripts/app/config.js.erb; \
    grep -q "env: 'selfhosted'" assets/javascripts/app/config.js.erb

COPY prepare.rb start.sh /devdocs/selfhost/
RUN chmod +x /devdocs/selfhost/start.sh && thor assets:compile

# Downloaded documentation sets live on the Railway volume.
VOLUME /devdocs/public/docs
EXPOSE 9292
CMD ["/devdocs/selfhost/start.sh"]
