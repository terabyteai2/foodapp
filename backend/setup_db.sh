#!/bin/bash
# Run once from a terminal: bash setup_db.sh
# Creates the PostgreSQL user + database for Rastarant.

set -e

DB_NAME="${DB_NAME:-rastarant_local}"
DB_USER="${DB_USER:-rastarant_pos}"
DB_PASS="${DB_PASS:-password}"

echo ""
echo "Setting up PostgreSQL for Rastarant..."
echo "  DB:   $DB_NAME"
echo "  User: $DB_USER"
echo ""

sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
    CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASS}';
    RAISE NOTICE 'Created user ${DB_USER}';
  ELSE
    ALTER ROLE ${DB_USER} WITH PASSWORD '${DB_PASS}';
    RAISE NOTICE 'Reset password for ${DB_USER}';
  END IF;
END
\$\$;
SQL

sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" \
  | grep -q 1 || sudo -u postgres createdb -O "${DB_USER}" "${DB_NAME}"

sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"
sudo -u postgres psql -d "${DB_NAME}" -c "GRANT ALL ON SCHEMA public TO ${DB_USER};"

echo ""
echo "✓ Local PostgreSQL ready!"
echo "  LOCAL_DATABASE_URL=postgresql+asyncpg://${DB_USER}:${DB_PASS}@localhost/${DB_NAME}"
echo "  Run: bash start.sh"
echo ""
