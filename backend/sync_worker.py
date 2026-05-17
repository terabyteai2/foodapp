import asyncio
import re
from contextlib import asynccontextmanager
from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Any

import httpx
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


@asynccontextmanager
async def _optional_cloud_session():
    if SupabaseSessionLocal is None:
        yield None
        return
    async with SupabaseSessionLocal() as session:
        yield session


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

    if SupabaseSessionLocal is None and not settings.has_supabase_rest:
        _last_result = {
            "ok": False,
            "skipped": True,
            "reason": "SUPABASE_DATABASE_URL or SUPABASE_SERVICE_ROLE_KEY is not configured.",
        }
        return _last_result
    if not await internet_available():
        _last_result = {"ok": False, "skipped": True, "reason": "Internet is unavailable."}
        return _last_result

    async with _sync_lock:
        max_batch = batch_size or settings.SYNC_BATCH_SIZE
        pushed = 0
        failed = 0
        details: list[dict[str, Any]] = []

        async with AsyncSessionLocal() as local_db, _optional_cloud_session() as cloud_db:
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
                        if SupabaseSessionLocal is not None:
                            cloud_row = model(**values)
                            await cloud_db.merge(cloud_row)
                            await cloud_db.commit()
                        else:
                            await _upsert_supabase_rest(model.__tablename__, values)

                        row.remote_id = values["remote_id"]
                        row.sync_status = "synced"
                        row.last_sync_error = None
                        row.synced_at = now
                        await local_db.commit()
                        pushed += 1
                    except Exception as error:
                        if cloud_db is not None:
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
        "configured": SupabaseSessionLocal is not None or settings.has_supabase_rest,
        "mode": "database" if SupabaseSessionLocal is not None else "rest" if settings.has_supabase_rest else "none",
        "localDatabase": await check_local_database(),
        "supabaseDatabase": await check_supabase_database() or await check_supabase_rest(),
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


def _json_ready(value: Any) -> Any:
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, list):
        return [_json_ready(item) for item in value]
    if isinstance(value, dict):
        return {key: _json_ready(item) for key, item in value.items()}
    return value


async def check_supabase_rest() -> bool:
    if not settings.has_supabase_rest:
        return False
    try:
        async with httpx.AsyncClient(timeout=8) as client:
            response = await client.get(
                f"{settings.supabase_rest_url}/restaurants",
                headers=_supabase_rest_headers(),
                params={"select": "id", "limit": "1"},
            )
        return response.status_code < 500
    except Exception:
        return False


async def _upsert_supabase_rest(table_name: str, values: dict[str, Any]) -> None:
    if not settings.has_supabase_rest:
        raise RuntimeError("Supabase REST sync is not configured.")
    headers = _supabase_rest_headers()
    headers["Prefer"] = "resolution=merge-duplicates,return=minimal"
    payload = _supabase_rest_payload(table_name, values)
    async with httpx.AsyncClient(timeout=20) as client:
        for _ in range(20):
            response = await client.post(
                f"{settings.supabase_rest_url}/{table_name}",
                headers=headers,
                params={"on_conflict": "id"},
                json=[payload],
            )
            if response.status_code in {200, 201, 204}:
                return
            missing_column = _missing_schema_column(response.text)
            if response.status_code == 400 and missing_column in payload:
                payload.pop(missing_column, None)
                continue
            break
    if response.status_code not in {200, 201, 204}:
        detail = response.text.strip()
        raise RuntimeError(
            f"Supabase REST upsert failed for {table_name}: "
            f"HTTP {response.status_code} {detail}"
        )


def _supabase_rest_headers() -> dict[str, str]:
    key = settings.supabase_service_role_key
    return {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }


def _missing_schema_column(response_text: str) -> str | None:
    match = re.search(r"Could not find the '([^']+)' column", response_text)
    if not match:
        return None
    return match.group(1)


def _supabase_rest_payload(table_name: str, values: dict[str, Any]) -> dict[str, Any]:
    payload = _json_ready(values)
    if table_name == "restaurants":
        return _only(payload, ("id", "name", "created_at", "updated_at"))
    if table_name == "outlets":
        return _only(payload, ("id", "restaurant_id", "name", "created_at", "updated_at"))
    if table_name == "menu_items":
        return {
            "id": payload["id"],
            "outlet_id": payload["outlet_id"],
            "name": payload["name"],
            "description": payload.get("description") or "",
            "category": payload.get("category") or "General",
            "price": payload.get("price") or 0,
            "image_url": payload.get("image_url"),
            "is_available": payload.get("is_available", True),
            "preparation_time_minutes": payload.get("preparation_time_minutes"),
            "tags": payload.get("tags") or [],
            "sync_status": payload.get("sync_status") or "pending",
            "version": payload.get("version") or 1,
            "deleted_at": payload.get("deleted_at"),
            "app_created_at": payload.get("created_at"),
            "app_updated_at": payload.get("updated_at"),
            "raw_payload": payload,
            "created_at": payload.get("created_at"),
            "updated_at": payload.get("updated_at"),
        }
    if table_name == "orders":
        order_no = payload.get("order_no")
        if not order_no:
            serial = payload.get("serial_number")
            order_no = f"#{serial}" if serial else str(payload["id"])[:8]
        return {
            "id": payload["id"],
            "outlet_id": payload["outlet_id"],
            "order_no": order_no,
            "source": payload.get("source") or "pos",
            "customer_name": payload.get("customer_name"),
            "table_no": payload.get("table_no"),
            "note": payload.get("notes"),
            "status": payload.get("status") or "pending",
            "total": payload.get("total_amount") or 0,
            "sync_status": payload.get("sync_status") or "pending",
            "version": payload.get("version") or 1,
            "app_created_at": payload.get("created_at"),
            "app_updated_at": payload.get("updated_at"),
            "raw_payload": payload,
            "created_at": payload.get("created_at"),
            "updated_at": payload.get("updated_at"),
        }
    if table_name == "order_items":
        return _only(
            payload,
            ("id", "order_id", "menu_item_id", "name", "qty", "price", "line_total"),
        )
    if table_name == "admin_accounts":
        return {
            "id": payload["id"],
            "restaurant_id": payload.get("restaurant_id"),
            "outlet_id": payload["outlet_id"],
            "email": payload["email"],
            "username": payload["username"],
            "password_salt": payload.get("password_salt") or "local",
            "password_hash": payload.get("password_hash") or "",
            "role": payload.get("role") or "owner",
            "is_active": payload.get("is_active") is not False,
            "created_at": payload.get("created_at"),
            "updated_at": payload.get("updated_at"),
        }
    return payload


def _only(values: dict[str, Any], keys: tuple[str, ...]) -> dict[str, Any]:
    return {key: values.get(key) for key in keys}
