#!/bin/sh
# Installs the documentation sets named in DEVDOCS_DOCS, then serves DevDocs.
# Any failure exits non-zero so Railway's ON_FAILURE restart policy applies.
set -eu
cd /devdocs
ruby selfhost/prepare.rb

bundle exec puma --bind "tcp://0.0.0.0:${PORT:-9292}" --environment production \
  --threads "${PUMA_MIN_THREADS:-0}:${PUMA_MAX_THREADS:-4}" config.ru &
puma=$!
trap 'kill -TERM "$puma" 2>/dev/null' TERM INT

# Sets that didn't fit in the boot budget: fetch them now, then hot-restart Puma
# (SIGUSR2 keeps the same process) so the new catalog is served.
if [ "$(cat public/docs/.pending 2>/dev/null || echo 0)" != "0" ]; then
  ( ruby selfhost/prepare.rb --background && kill -USR2 "$puma" ) &
fi

# Exit with Puma's status; a crash or an OOM kill is non-zero.
set +e
wait "$puma"; status=$?
# A trapped SIGTERM interrupts the first wait; wait again for Puma to finish.
if kill -0 "$puma" 2>/dev/null; then wait "$puma"; status=$?; fi
exit "$status"
