from collections.abc import AsyncIterator

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from config import settings

engine = create_async_engine(settings.local_database_url, echo=False, pool_pre_ping=True)
AsyncSessionLocal = async_sessionmaker(engine, expire_on_commit=False)

supabase_engine: AsyncEngine | None = None
SupabaseSessionLocal: async_sessionmaker[AsyncSession] | None = None
if settings.has_supabase_database:
    supabase_engine = create_async_engine(
        settings.supabase_database_url,
        echo=False,
        pool_pre_ping=True,
    )
    SupabaseSessionLocal = async_sessionmaker(supabase_engine, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


async def get_db() -> AsyncSession:
    async with AsyncSessionLocal() as session:
        yield session


async def get_local_session() -> AsyncIterator[AsyncSession]:
    async with AsyncSessionLocal() as session:
        yield session


async def get_supabase_session() -> AsyncIterator[AsyncSession]:
    if SupabaseSessionLocal is None:
        raise RuntimeError("SUPABASE_DATABASE_URL is not configured.")
    async with SupabaseSessionLocal() as session:
        yield session


async def create_tables() -> None:
    async with engine.begin() as conn:
        from models import Base as ModelBase  # noqa: F401 – registers models

        await conn.run_sync(ModelBase.metadata.create_all)
        await _ensure_sync_columns(conn)


async def create_supabase_tables() -> None:
    if supabase_engine is None or not settings.CREATE_SUPABASE_TABLES:
        return
    async with supabase_engine.begin() as conn:
        from models import Base as ModelBase  # noqa: F401 – registers models

        await conn.run_sync(ModelBase.metadata.create_all)
        await _ensure_sync_columns(conn)


async def check_local_database() -> bool:
    try:
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
        return True
    except Exception:
        return False


async def check_supabase_database() -> bool:
    if supabase_engine is None:
        return False
    try:
        async with supabase_engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
        return True
    except Exception:
        return False


async def _ensure_sync_columns(conn) -> None:
    sync_tables = (
        "restaurants",
        "outlets",
        "admin_accounts",
        "devices",
        "menu_items",
        "orders",
        "order_items",
        "pos_tables",
        "customers",
        "sales",
        "payments",
        "bkash_sessions",
    )
    for table in sync_tables:
        await conn.execute(text(f"ALTER TABLE IF EXISTS {table} ADD COLUMN IF NOT EXISTS local_id TEXT"))
        await conn.execute(text(f"ALTER TABLE IF EXISTS {table} ADD COLUMN IF NOT EXISTS remote_id TEXT"))
        await conn.execute(
            text(
                f"ALTER TABLE IF EXISTS {table} "
                "ADD COLUMN IF NOT EXISTS sync_status TEXT DEFAULT 'pending'"
            )
        )
        await conn.execute(text(f"ALTER TABLE IF EXISTS {table} ADD COLUMN IF NOT EXISTS last_sync_error TEXT"))
        await conn.execute(text(f"ALTER TABLE IF EXISTS {table} ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ"))
        await conn.execute(text(f"ALTER TABLE IF EXISTS {table} ADD COLUMN IF NOT EXISTS synced_at TIMESTAMPTZ"))
        await conn.execute(text(f"ALTER TABLE IF EXISTS {table} ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ"))
        await conn.execute(text(f"UPDATE {table} SET local_id = id WHERE local_id IS NULL"))
        await conn.execute(text(f"UPDATE {table} SET sync_status = 'pending' WHERE sync_status IS NULL"))
        await conn.execute(text(f"UPDATE {table} SET created_at = NOW() WHERE created_at IS NULL"))
        await conn.execute(text(f"UPDATE {table} SET updated_at = created_at WHERE updated_at IS NULL"))
        await conn.execute(
            text(
                f"CREATE UNIQUE INDEX IF NOT EXISTS ix_{table}_local_id "
                f"ON {table}(local_id) WHERE local_id IS NOT NULL"
            )
        )
    await conn.execute(text("ALTER TABLE IF EXISTS orders ADD COLUMN IF NOT EXISTS table_no TEXT"))
    await conn.execute(text("ALTER TABLE IF EXISTS orders ADD COLUMN IF NOT EXISTS customer_id TEXT"))
    await conn.execute(text("ALTER TABLE IF EXISTS orders ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'unpaid'"))
    await conn.execute(text("ALTER TABLE IF EXISTS admin_accounts ADD COLUMN IF NOT EXISTS restaurant_id TEXT"))
    await conn.execute(text("ALTER TABLE IF EXISTS admin_accounts ADD COLUMN IF NOT EXISTS google_uid TEXT"))
    await conn.execute(text("ALTER TABLE IF EXISTS admin_accounts ADD COLUMN IF NOT EXISTS password_salt TEXT DEFAULT ''"))
    await conn.execute(text("ALTER TABLE IF EXISTS admin_accounts ADD COLUMN IF NOT EXISTS role TEXT DEFAULT 'owner'"))
    await conn.execute(text("ALTER TABLE IF EXISTS admin_accounts ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE"))
    await conn.execute(text("ALTER TABLE IF EXISTS menu_items ADD COLUMN IF NOT EXISTS video_url TEXT"))
    await conn.execute(text("ALTER TABLE IF EXISTS outlets ADD COLUMN IF NOT EXISTS banner_url TEXT"))
    await conn.execute(text("ALTER TABLE IF EXISTS outlets ADD COLUMN IF NOT EXISTS video_url TEXT"))
    await conn.execute(text("ALTER TABLE IF EXISTS outlets ADD COLUMN IF NOT EXISTS gallery_images JSONB"))
    await conn.execute(text("ALTER TABLE IF EXISTS devices ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ"))
    await conn.execute(text("ALTER TABLE IF EXISTS devices ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ"))
    await conn.execute(text("ALTER TABLE IF EXISTS bkash_sessions ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ"))
