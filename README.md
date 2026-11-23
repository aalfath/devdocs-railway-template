[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/devdocs-1?utm_medium=integration&utm_source=button&utm_campaign=devdocs)

# DevDocs on Railway

One-click Railway template for [DevDocs](https://github.com/freeCodeCamp/devdocs) (freeCodeCamp, MPL-2.0): a fast, searchable, offline-capable browser for the API documentation of hundreds of languages, frameworks and tools.

## What it deploys

One service, **DevDocs**, built from this repo's `Dockerfile`:

- the official `ruby:4.0.9-slim` image pinned by digest (`sha256:d8cb2c07…`), with DevDocs checked out at the pinned upstream commit [`e6ee9b5`](https://github.com/freeCodeCamp/devdocs/commit/e6ee9b5673346e73962e037146de2b4f5109ae0f) (2026-11-20). Upstream publishes no releases, and its `ghcr.io/freecodecamp/devdocs` image hasn't been rebuilt since 2026-02-01, so the template builds from source;
- the app runs in production mode with Puma on `PORT`, serves the documentation itself (not from devdocs.io's CDN), and sends no analytics;
- a volume at `/devdocs/public/docs` holds the downloaded documentation sets, so they survive restarts and redeploys;
- health check: `GET /ping`.

On every start, `selfhost/prepare.rb` downloads any set listed in `DEVDOCS_DOCS` that isn't on the volume yet (from `downloads.devdocs.io`), rebuilds the catalog and then starts the server. New visitors get those sets enabled. Visitors can enable or disable any installed set under **Preferences**.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `PORT` | `9292` | Port Puma listens on. |
| `DEVDOCS_DOCS` | `css dom html http javascript` | Documentation sets to install, separated by spaces or commas. Use the slugs from devdocs.io's URLs (`python`, `typescript`, `node`, `react`, `postgresql~17`…), or `all` for everything (about 9 GB). |

Optional (not in the template): `DEVDOCS_REFRESH_DAYS` (default `30`: re-download every installed set this often to pick up new doc versions; `0` turns it off), `DEVDOCS_BOOT_BUDGET` (default `180` seconds: downloads on start stop after this, and the rest continue in the background with a hot restart when done), `DEVDOCS_DOWNLOADS_URL` (mirror for the doc packages).

Removing a set from `DEVDOCS_DOCS` doesn't delete it. To free its space, delete its folder from the volume.

## Resources

About 0.13 GB RAM when idle and up to about 0.25 GB while it downloads, so it runs within Railway's 0.5 GB per-service limit on the Free and Trial plans. Disk use is about twice the compressed size of the sets you pick (the 5 defaults take about 230 MB).

## Updates

Railway tells deployers when this repo's `main` branch changes. Each update bumps the pinned upstream commit or the Ruby base image and is described in [`CHANGELOG.md`](CHANGELOG.md). Applying an update rebuilds the image. The downloaded documentation on the volume is kept.

## Local run

```sh
docker build -t devdocs-railway .
docker run -p 9292:9292 -v devdocs-docs:/devdocs/public/docs devdocs-railway
```

The app redirects plain HTTP to HTTPS (it expects Railway's proxy), so locally send `X-Forwarded-Proto: https` or put it behind a TLS proxy.
