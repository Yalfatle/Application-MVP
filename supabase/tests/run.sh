#!/usr/bin/env bash
# Applies every migration to a throwaway Postgres and runs the permission tests.
#   PGHOST=localhost PGPORT=5432 PGUSER=postgres ./supabase/tests/run.sh
set -euo pipefail
cd "$(dirname "$0")"
psql -v ON_ERROR_STOP=1 -q -d postgres -c "drop database if exists mukhtabarat_test" -c "create database mukhtabarat_test"
export PGDATABASE=mukhtabarat_test
psql -v ON_ERROR_STOP=1 -q -f supabase_stub.sql 2>&1 | grep -v -E "wal_level|HINT" || true
for f in ../migrations/*.sql; do
  echo "applying $(basename "$f")"
  # pg_net and pg_cron exist on Supabase; the stub provides stand-ins.
  grep -vE "create extension if not exists (pg_net|pg_cron)" "$f" | psql -v ON_ERROR_STOP=1 -q >/dev/null
done
DATABASE_URL="dbname=mukhtabarat_test" python3 permissions_test.py
