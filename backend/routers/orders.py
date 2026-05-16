from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Header, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from auth import get_current_outlet_id
from database import get_db
from models import Order, OrderItem
from routers.ws import manager
from schemas import OrderPayload, OrderStatusUpdate, ok

router = APIRouter()


def _order_to_dict(order: Order) -> dict:
    return {
        "id": order.id,
        "outletId": order.outlet_id,
        "serialNumber": order.serial_number,
        "source": order.source,
        "status": order.status,
        "totalAmount": float(order.total_amount),
        "items": order.items,
        "notes": order.notes,
        "tableNo": order.table_no,
        "paymentStatus": order.payment_status,
        "localId": order.local_id,
        "remoteId": order.remote_id,
        "syncStatus": order.sync_status,
        "lastSyncError": order.last_sync_error,
        "createdAt": order.created_at.isoformat(),
        "updatedAt": order.updated_at.isoformat(),
        "syncedAt": order.synced_at.isoformat() if order.synced_at else None,
    }


def _order_items(order_id: str, outlet_id: str, items: list) -> list[OrderItem]:
    rows: list[OrderItem] = []
    for raw in items:
        if not isinstance(raw, dict):
            continue
        qty = int(raw.get("qty") or raw.get("quantity") or 1)
        price = float(raw.get("price") or 0)
        rows.append(
            OrderItem(
                order_id=order_id,
                outlet_id=outlet_id,
                menu_item_id=str(
                    raw.get("menuItemId") or raw.get("menu_item_id") or raw.get("id") or ""
                ),
                name=str(raw.get("name") or "Item"),
                qty=qty,
                price=price,
                line_total=float(raw.get("lineTotal") or raw.get("line_total") or price * qty),
            )
        )
    return rows


@router.get("/outlets/{outlet_id}/orders")
async def pull_orders(
    outlet_id: str,
    since: str | None = None,
    current_outlet: str = Depends(get_current_outlet_id),
    db: AsyncSession = Depends(get_db),
):
    query = select(Order).where(Order.outlet_id == outlet_id).order_by(Order.created_at.desc())
    if since:
        dt = datetime.fromisoformat(since.replace("Z", "+00:00"))
        query = query.where(Order.updated_at > dt)
    orders = (await db.execute(query)).scalars().all()
    return ok([_order_to_dict(o) for o in orders])


@router.post("/outlets/{outlet_id}/orders")
async def push_order(
    outlet_id: str,
    body: OrderPayload,
    current_outlet: str = Depends(get_current_outlet_id),
    db: AsyncSession = Depends(get_db),
    idempotency_key: str | None = Header(None, alias="Idempotency-Key"),
):
    existing = (await db.execute(select(Order).where(Order.id == body.id))).scalar_one_or_none()
    if existing:
        return ok(_order_to_dict(existing))

    now = datetime.now(timezone.utc)
    order = Order(
        id=body.id,
        outlet_id=outlet_id,
        serial_number=body.serialNumber,
        source=body.source,
        status=body.status,
        total_amount=body.totalAmount,
        items=body.items,
        notes=body.notes,
        created_at=now,
        updated_at=now,
    )
    db.add(order)
    for item in _order_items(order.id, outlet_id, body.items):
        db.add(item)
    await db.commit()
    await db.refresh(order)

    await manager.broadcast(outlet_id, {"type": "order_created", "data": _order_to_dict(order)})
    return ok(_order_to_dict(order))


@router.patch("/outlets/{outlet_id}/orders/{order_id}/status")
async def update_order_status(
    outlet_id: str,
    order_id: str,
    body: OrderStatusUpdate,
    current_outlet: str = Depends(get_current_outlet_id),
    db: AsyncSession = Depends(get_db),
    idempotency_key: str | None = Header(None, alias="Idempotency-Key"),
):
    order = (await db.execute(select(Order).where(Order.id == order_id))).scalar_one_or_none()
    if order is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Order not found.")

    order.status = body.status
    order.updated_at = datetime.now(timezone.utc)
    order.sync_status = "pending"
    order.synced_at = None
    await db.commit()
    await db.refresh(order)

    await manager.broadcast(outlet_id, {"type": "order_status_updated", "data": _order_to_dict(order)})
    return ok(_order_to_dict(order))
