#!/bin/sh
# Installs the documentation sets named in DEVDOCS_DOCS, then serves DevDocs.
# Any failure exits non-zero so Railway's ON_FAILURE restart policy applies.
set -eu
cd /devdocs
ruby selfhost/prepare.rb
exec bundle exec puma --bind "tcp://0.0.0.0:${PORT:-9292}" --environment production \
  --threads "${PUMA_MIN_THREADS:-0}:${PUMA_MAX_THREADS:-4}" config.ru
