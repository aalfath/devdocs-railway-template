# Changelog

Breaking changes are listed first in each entry.

## 2026-11-23: first release

- DevDocs at upstream commit `e6ee9b5673346e73962e037146de2b4f5109ae0f` (2026-11-20), on `ruby:4.0.9-slim@sha256:d8cb2c0714bdaba0f318af897a01d2dbde3cfa8e62d47e99cea55feb13c0e90d`.
- Documentation sets download on start into the `/devdocs/public/docs` volume (`DEVDOCS_DOCS`, default `css dom html http javascript`), with a 180-second first-boot budget and the rest downloaded in the background.
- Production mode on Puma, docs served locally, no analytics, `/ping` health check over plain HTTP.
