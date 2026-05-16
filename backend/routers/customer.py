"""Public customer-facing endpoints — no device token required."""

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import joinedload

from database import get_db
from models import MenuItem, Order, OrderItem, Outlet
from routers.ws import manager

router = APIRouter(prefix="/customer", tags=["customer"])


# ── helpers ────────────────────────────────────────────────────────────────────

def _ok(data):
    return {"ok": True, "data": data}


def _item_to_dict(item: MenuItem) -> dict:
    return {
        "id": item.id,
        "name": item.name,
        "description": item.description or "",
        "price": float(item.price),
        "category": item.category or "General",
        "isAvailable": item.is_available,
        "imageUrl": item.image_url,
        "videoUrl": item.video_url,
    }


async def _get_outlet(outlet_id: str, db: AsyncSession) -> Outlet:
    outlet = (
        await db.execute(select(Outlet).where(Outlet.id == outlet_id))
    ).scalar_one_or_none()
    if outlet is None:
        raise HTTPException(status_code=404, detail="Outlet not found")
    return outlet


def _outlet_info(outlet: Outlet) -> dict:
    return {
        "outletId": outlet.id,
        "restaurantName": outlet.restaurant.name if outlet.restaurant else "",
        "outletName": outlet.name,
        "bannerUrl": outlet.banner_url,
        "videoUrl": outlet.video_url,
        "galleryImages": outlet.gallery_images or [],
    }


@router.get("/default")
async def get_default_outlet(db: AsyncSession = Depends(get_db)):
    outlet = (
        await db.execute(
            select(Outlet)
            .options(joinedload(Outlet.restaurant))
            .order_by(Outlet.created_at.asc())
        )
    ).scalars().first()
    if outlet is None:
        raise HTTPException(status_code=404, detail="No outlet found")
    return _ok(_outlet_info(outlet))


# ── GET menu ──────────────────────────────────────────────────────────────────

@router.get("/{outlet_id}/menu")
async def get_public_menu(
    outlet_id: str,
    db: AsyncSession = Depends(get_db),
):
    """Return available menu items for the customer-facing menu page."""
    await _get_outlet(outlet_id, db)
    items = (
        await db.execute(
            select(MenuItem)
            .where(
                MenuItem.outlet_id == outlet_id,
                MenuItem.is_available == True,
                MenuItem.deleted_at == None,
            )
            .order_by(MenuItem.category, MenuItem.name)
        )
    ).scalars().all()
    return _ok([_item_to_dict(i) for i in items])


# ── POST order ────────────────────────────────────────────────────────────────

class CustomerOrderItem(BaseModel):
    menuItemId: str
    name: str
    qty: int
    price: float


class CustomerOrderRequest(BaseModel):
    items: list[CustomerOrderItem]
    tableNo: str | None = None
    note: str | None = None


@router.post("/{outlet_id}/orders")
async def place_customer_order(
    outlet_id: str,
    body: CustomerOrderRequest,
    db: AsyncSession = Depends(get_db),
):
    """Place an order from the customer menu web app."""
    if not body.items:
        raise HTTPException(status_code=422, detail="Order must contain at least one item")

    await _get_outlet(outlet_id, db)

    total = sum(item.price * item.qty for item in body.items)
    now = datetime.now(timezone.utc)
    order_id = str(uuid.uuid4())

    items_payload = [
        {
            "menuItemId": item.menuItemId,
            "name": item.name,
            "qty": item.qty,
            "price": item.price,
            "lineTotal": round(item.price * item.qty, 2),
        }
        for item in body.items
    ]

    order = Order(
        id=order_id,
        outlet_id=outlet_id,
        source="customer_web",
        status="pending",
        total_amount=round(total, 2),
        items=items_payload,
        notes=body.tableNo and f"Table {body.tableNo}" or body.note,
        table_no=body.tableNo,
        created_at=now,
        updated_at=now,
    )
    db.add(order)
    for item in items_payload:
        db.add(
            OrderItem(
                order_id=order_id,
                outlet_id=outlet_id,
                menu_item_id=item["menuItemId"],
                name=item["name"],
                qty=item["qty"],
                price=item["price"],
                line_total=item["lineTotal"],
            )
        )
    await db.commit()
    await db.refresh(order)

    # Assign a 1-based serial number scoped to this outlet
    count_res = await db.execute(
        select(func.count()).select_from(Order).where(Order.outlet_id == outlet_id)
    )
    order.serial_number = count_res.scalar()
    await db.commit()

    # Broadcast to the admin POS via WebSocket
    await manager.broadcast(
        outlet_id,
        {
            "type": "order_created",
            "data": {
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
                "createdAt": order.created_at.isoformat(),
                "updatedAt": order.updated_at.isoformat(),
                "syncedAt": order.synced_at.isoformat() if order.synced_at else None,
            },
        },
    )

    return _ok({
        "orderId": order.id,
        "serialNumber": order.serial_number,
        "status": order.status,
        "total": float(order.total_amount),
        "items": order.items,
        "notes": order.notes,
    })


# ── GET restaurant info ────────────────────────────────────────────────────────

@router.get("/{outlet_id}/info")
async def get_outlet_info(
    outlet_id: str,
    db: AsyncSession = Depends(get_db),
):
    """Return restaurant/outlet name for display on the customer menu page."""
    outlet = (
        await db.execute(
            select(Outlet)
            .where(Outlet.id == outlet_id)
            .options(joinedload(Outlet.restaurant))
        )
    ).scalar_one_or_none()
    if outlet is None:
        raise HTTPException(status_code=404, detail="Outlet not found")
    return _ok(_outlet_info(outlet))
