import asyncio
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import func, inspect as sa_inspect, select

from config import settings
from database import AsyncSessionLocal, SupabaseSessionLocal, check_local_database, check_supabase_database
from models import (
    AdminAccount,
    BkashSession,
    Customer,
    Device,
    MenuItem,
    Order,
    OrderItem,
    Outlet,
    Payment,
    PosTable,
    Restaurant,
    Sale,
)

SYNC_MODELS = (
    Restaurant,
    Outlet,
    AdminAccount,
    Device,
    MenuItem,
    Customer,
    PosTable,
    Order,
    OrderItem,
    Sale,
    Payment,
    BkashSession,
)

SYNCABLE_STATUSES = ("pending", "failed")
_sync_lock = asyncio.Lock()
_last_sync_at: datetime | None = None
_last_error: str | None = None
_last_result: dict[str, Any] = {}


async def internet_available(timeout: float = 3.0) -> bool:
    try:
        reader, writer = await asyncio.wait_for(
            asyncio.open_connection("8.8.8.8", 53),
            timeout=timeout,
        )
        writer.close()
        await writer.wait_closed()
        del reader
        return True
    except Exception:
        return False


async def sync_once(batch_size: int | None = None) -> dict[str, Any]:
    global _last_error, _last_result, _last_sync_at

    if SupabaseSessionLocal is None:
        _last_result = {"ok": False, "skipped": True, "reason": "SUPABASE_DATABASE_URL is not configured."}
        return _last_result
    if not await internet_available():
        _last_result = {"ok": False, "skipped": True, "reason": "Internet is unavailable."}
        return _last_result

    async with _sync_lock:
        max_batch = batch_size or settings.SYNC_BATCH_SIZE
        pushed = 0
        failed = 0
        details: list[dict[str, Any]] = []

        async with AsyncSessionLocal() as local_db, SupabaseSessionLocal() as cloud_db:
            for model in SYNC_MODELS:
                remaining = max_batch - pushed
                if remaining <= 0:
                    break
                rows = (
                    await local_db.execute(
                        select(model)
                        .where(model.sync_status.in_(SYNCABLE_STATUSES))
                        .order_by(model.updated_at.asc())
                        .limit(remaining)
                    )
                ).scalars().all()

                for row in rows:
                    row.sync_status = "syncing"
                    row.last_sync_error = None
                    await local_db.commit()
                    try:
                        now = datetime.now(timezone.utc)
                        values = _column_values(row)
                        values["remote_id"] = values.get("remote_id") or values["id"]
                        values["sync_status"] = "synced"
                        values["last_sync_error"] = None
                        values["synced_at"] = now
                        cloud_row = model(**values)
                        await cloud_db.merge(cloud_row)
                        await cloud_db.commit()

                        row.remote_id = values["remote_id"]
                        row.sync_status = "synced"
                        row.last_sync_error = None
                        row.synced_at = now
                        await local_db.commit()
                        pushed += 1
                    except Exception as error:
                        await cloud_db.rollback()
                        row.sync_status = "failed"
                        row.last_sync_error = str(error)
                        await local_db.commit()
                        failed += 1
                        details.append(
                            {
                                "table": row.__class__.__tablename__,
                                "id": row.id,
                                "error": str(error),
                            }
                        )

        _last_sync_at = datetime.now(timezone.utc)
        _last_error = None if failed == 0 else f"{failed} record(s) failed to sync."
        _last_result = {
            "ok": failed == 0,
            "pushed": pushed,
            "failed": failed,
            "lastSyncAt": _last_sync_at.isoformat(),
            "errors": details[:20],
        }
        return _last_result


async def sync_status() -> dict[str, Any]:
    pending = 0
    syncing = 0
    synced = 0
    failed = 0
    by_table: dict[str, dict[str, int]] = {}

    async with AsyncSessionLocal() as db:
        for model in SYNC_MODELS:
            rows = (
                await db.execute(
                    select(model.sync_status, func.count())
                    .group_by(model.sync_status)
                )
            ).all()
            table_counts = {status or "unknown": count for status, count in rows}
            by_table[model.__tablename__] = table_counts
            pending += table_counts.get("pending", 0)
            syncing += table_counts.get("syncing", 0)
            synced += table_counts.get("synced", 0)
            failed += table_counts.get("failed", 0)

    return {
        "configured": SupabaseSessionLocal is not None,
        "localDatabase": await check_local_database(),
        "supabaseDatabase": await check_supabase_database(),
        "internet": await internet_available(),
        "pending": pending,
        "syncing": syncing,
        "synced": synced,
        "failed": failed,
        "lastSyncAt": _last_sync_at.isoformat() if _last_sync_at else None,
        "lastError": _last_error,
        "lastResult": _last_result,
        "byTable": by_table,
    }


async def run_periodic_sync(stop_event: asyncio.Event) -> None:
    while not stop_event.is_set():
        try:
            await sync_once()
        except Exception as error:
            global _last_error
            _last_error = str(error)
        try:
            await asyncio.wait_for(
                stop_event.wait(),
                timeout=max(10, settings.SYNC_INTERVAL_SECONDS),
            )
        except asyncio.TimeoutError:
            pass


def _column_values(row: Any) -> dict[str, Any]:
    mapper = sa_inspect(row.__class__)
    return {column.key: getattr(row, column.key) for column in mapper.columns}
