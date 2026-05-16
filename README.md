# Restaurant POS Offline-First Setup

This POS now runs local-first:

- FastAPI uses local PostgreSQL first through `LOCAL_DATABASE_URL`.
- Supabase PostgreSQL remains the cloud sync database through `SUPABASE_DATABASE_URL`.
- Customer phones on the same WiFi open the menu from the LAN server, for example `http://192.168.1.20:8000/menu`.
- Firebase Auth can remain for online login, but POS data is not stored in Firestore.

## Install Local PostgreSQL

Ubuntu/Debian:

```bash
sudo apt update
sudo apt install postgresql postgresql-contrib
```

Create the local POS database:

```bash
cd backend
bash setup_db.sh
```

By default this creates:

```text
database: rastarant_local
user: rastarant_pos
password: password
```

## Environment

Copy the example env file:

```bash
cd backend
cp .env.example .env
```

Set local PostgreSQL:

```env
LOCAL_DATABASE_URL=postgresql+asyncpg://rastarant_pos:password@localhost/rastarant_local
```

Set Supabase cloud sync, using the direct PostgreSQL connection string from Supabase:

```env
SUPABASE_DATABASE_URL=postgresql+asyncpg://postgres.PROJECT_REF:PASSWORD@aws-0-region.pooler.supabase.com:6543/postgres
```

`DATABASE_URL` is still accepted as a fallback for older setups, but new local installs should use `LOCAL_DATABASE_URL`.

## Run Backend Locally

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
bash start.sh
```

The backend listens on `0.0.0.0:8000`, so other devices on the same WiFi router can connect.

Find your LAN IP:

```bash
hostname -I
```

If your IP is `192.168.1.20`, use:

```text
http://192.168.1.20:8000
```

## Customer Menu QR

Build the React customer menu:

```bash
cd backend
bash build_frontend.sh
```

In the Flutter admin app, set the API URL to the LAN server, for example:

```text
http://192.168.1.20:8000
```

Then open Settings → Table QR Codes. The QR should point to:

```text
http://192.168.1.20:8000/menu
```

Customers must be connected to the same WiFi router. Scanning the QR opens the menu, loads the default outlet, and sends orders to the local FastAPI server.

## Sync Model

All POS writes go to local PostgreSQL first. The backend adds sync tracking fields to POS tables:

- `local_id`
- `remote_id`
- `sync_status`: `pending`, `syncing`, `synced`, `failed`
- `last_sync_error`
- `created_at`
- `updated_at`
- `synced_at`

Local IDs are UUID strings, so local records can be uploaded without colliding with Supabase records.

When internet is available, the background sync worker uploads pending/failed local records to Supabase PostgreSQL. If internet is unavailable, records stay local. When internet returns, the worker uploads the queue.

Manual sync endpoint:

```bash
curl -X POST http://localhost:8000/sync/now
```

Health endpoints:

```text
GET /health
GET /health/local-database
GET /health/internet
GET /health/supabase
GET /health/sync
GET /sync/status
POST /sync/now
```

## Supabase Manual Steps

If `CREATE_SUPABASE_TABLES=true`, the backend tries to create/mirror the needed tables and sync columns automatically.

If Supabase permissions block automatic schema updates, open Supabase SQL Editor and run:

```text
backend/sql/offline_first_sync.sql
```

Also confirm:

- Use a direct PostgreSQL connection string, not the Supabase REST URL.
- The database user has permission to create/alter tables, or run the SQL manually.
- Do not use Firestore for POS data.
