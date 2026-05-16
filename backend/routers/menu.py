import base64
import os
import uuid
from datetime import datetime, timezone

import pydantic
from fastapi import APIRouter, Depends, File, Header, HTTPException, UploadFile, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from auth import get_current_outlet_id
from config import settings
from database import get_db
from models import MenuItem, Outlet
from routers.ws import manager
from schemas import ImageUploadRequest, MenuItemPayload, ok

router = APIRouter()


def _item_to_dict(item: MenuItem) -> dict:
    return {
        "id": item.id,
        "outletId": item.outlet_id,
        "name": item.name,
        "description": item.description,
        "price": float(item.price),
        "category": item.category,
        "isAvailable": item.is_available,
        "imageUrl": item.image_url,
        "version": item.version,
        "localId": item.local_id,
        "remoteId": item.remote_id,
        "syncStatus": item.sync_status,
        "lastSyncError": item.last_sync_error,
        "createdAt": item.created_at.isoformat(),
        "updatedAt": item.updated_at.isoformat(),
        "syncedAt": item.synced_at.isoformat() if item.synced_at else None,
        "deletedAt": item.deleted_at.isoformat() if item.deleted_at else None,
    }


@router.get("/outlets/{outlet_id}/menu")
async def pull_menu(
    outlet_id: str,
    since: str | None = None,
    current_outlet: str = Depends(get_current_outlet_id),
    db: AsyncSession = Depends(get_db),
):
    query = select(MenuItem).where(MenuItem.outlet_id == outlet_id)
    if since:
        dt = datetime.fromisoformat(since.replace("Z", "+00:00"))
        query = query.where(MenuItem.updated_at > dt)
    items = (await db.execute(query)).scalars().all()
    return ok([_item_to_dict(i) for i in items])


@router.post("/outlets/{outlet_id}/menu")
async def push_menu_item(
    outlet_id: str,
    body: MenuItemPayload,
    current_outlet: str = Depends(get_current_outlet_id),
    db: AsyncSession = Depends(get_db),
    idempotency_key: str | None = Header(None, alias="Idempotency-Key"),
):
    existing = (await db.execute(select(MenuItem).where(MenuItem.id == body.id))).scalar_one_or_none()
    if existing:
        return ok(_item_to_dict(existing))

    item = MenuItem(
        id=body.id,
        outlet_id=outlet_id,
        name=body.name,
        description=body.description,
        price=body.price,
        category=body.category,
        is_available=body.isAvailable,
        image_url=body.imageUrl,
        version=body.version,
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )
    db.add(item)
    await db.commit()
    await db.refresh(item)

    await manager.broadcast(outlet_id, {"type": "menu_updated", "data": _item_to_dict(item)})
    return ok(_item_to_dict(item))


@router.patch("/outlets/{outlet_id}/menu/{item_id}")
async def update_menu_item(
    outlet_id: str,
    item_id: str,
    body: MenuItemPayload,
    current_outlet: str = Depends(get_current_outlet_id),
    db: AsyncSession = Depends(get_db),
    idempotency_key: str | None = Header(None, alias="Idempotency-Key"),
):
    item = (await db.execute(select(MenuItem).where(MenuItem.id == item_id))).scalar_one_or_none()
    if item is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Menu item not found.")

    item.name = body.name
    item.description = body.description
    item.price = body.price
    item.category = body.category
    item.is_available = body.isAvailable
    item.image_url = body.imageUrl
    item.version = body.version
    item.updated_at = datetime.now(timezone.utc)
    item.sync_status = "pending"
    item.synced_at = None
    await db.commit()
    await db.refresh(item)

    await manager.broadcast(outlet_id, {"type": "menu_updated", "data": _item_to_dict(item)})
    return ok(_item_to_dict(item))


@router.delete("/outlets/{outlet_id}/menu/{item_id}")
async def delete_menu_item(
    outlet_id: str,
    item_id: str,
    current_outlet: str = Depends(get_current_outlet_id),
    db: AsyncSession = Depends(get_db),
    idempotency_key: str | None = Header(None, alias="Idempotency-Key"),
):
    item = (await db.execute(select(MenuItem).where(MenuItem.id == item_id))).scalar_one_or_none()
    if item is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Menu item not found.")

    item.deleted_at = datetime.now(timezone.utc)
    item.updated_at = datetime.now(timezone.utc)
    item.sync_status = "pending"
    item.synced_at = None
    await db.commit()

    await manager.broadcast(outlet_id, {"type": "menu_updated", "data": _item_to_dict(item)})
    return ok({"deleted": True})


@router.post("/outlets/{outlet_id}/menu/images")
async def upload_menu_image(
    outlet_id: str,
    body: ImageUploadRequest,
    current_outlet: str = Depends(get_current_outlet_id),
):
    # Parse data URL:  data:image/jpeg;base64,<data>
    try:
        header, encoded = body.dataUrl.split(",", 1)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid dataUrl format.")

    image_bytes = base64.b64decode(encoded)
    ext = "jpg"
    if "png" in header:
        ext = "png"

    filename = f"{uuid.uuid4()}.{ext}"
    os.makedirs(settings.IMAGES_DIR, exist_ok=True)
    filepath = os.path.join(settings.IMAGES_DIR, filename)

    with open(filepath, "wb") as f:
        f.write(image_bytes)

    public_url = f"{settings.BASE_URL}/uploads/menu_images/{filename}"
    return ok({"publicUrl": public_url})


# ── Outlet hero image endpoints ────────────────────────────────────────────────

class OutletMediaPatch(pydantic.BaseModel):
    videoUrl: str | None = None


@router.post("/outlets/{outlet_id}/images")
async def upload_outlet_image(
    outlet_id: str,
    body: ImageUploadRequest,
    current_outlet: str = Depends(get_current_outlet_id),
    db: AsyncSession = Depends(get_db),
):
    outlet = (await db.execute(select(Outlet).where(Outlet.id == outlet_id))).scalar_one_or_none()
    if outlet is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Outlet not found.")

    gallery = list(outlet.gallery_images or [])
    if len(gallery) >= 5:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Maximum 5 hero images allowed.")

    try:
        header, encoded = body.dataUrl.split(",", 1)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid dataUrl format.")

    image_bytes = base64.b64decode(encoded)
    ext = "png" if "png" in header else "jpg"
    filename = f"{uuid.uuid4()}.{ext}"
    os.makedirs(settings.OUTLET_IMAGES_DIR, exist_ok=True)
    with open(os.path.join(settings.OUTLET_IMAGES_DIR, filename), "wb") as f:
        f.write(image_bytes)

    public_url = f"{settings.BASE_URL}/uploads/outlet_images/{filename}"
    gallery.append(public_url)
    outlet.gallery_images = gallery
    outlet.sync_status = "pending"
    outlet.synced_at = None
    await db.commit()
    return ok({"publicUrl": public_url, "galleryImages": gallery})


@router.delete("/outlets/{outlet_id}/images/{index}")
async def delete_outlet_image(
    outlet_id: str,
    index: int,
    current_outlet: str = Depends(get_current_outlet_id),
    db: AsyncSession = Depends(get_db),
):
    outlet = (await db.execute(select(Outlet).where(Outlet.id == outlet_id))).scalar_one_or_none()
    if outlet is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Outlet not found.")

    gallery = list(outlet.gallery_images or [])
    if index < 0 or index >= len(gallery):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Image index out of range.")

    gallery.pop(index)
    outlet.gallery_images = gallery
    outlet.sync_status = "pending"
    outlet.synced_at = None
    await db.commit()
    return ok({"galleryImages": gallery})


@router.post("/outlets/{outlet_id}/video")
async def upload_outlet_video(
    outlet_id: str,
    file: UploadFile = File(...),
    current_outlet: str = Depends(get_current_outlet_id),
    db: AsyncSession = Depends(get_db),
):
    content = await file.read()
    if len(content) > settings.VIDEO_MAX_BYTES:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail=f"Video too large. Maximum {settings.VIDEO_MAX_BYTES // 1024 // 1024} MB allowed.")

    outlet = (await db.execute(select(Outlet).where(Outlet.id == outlet_id))).scalar_one_or_none()
    if outlet is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Outlet not found.")

    name = file.filename or "video.mp4"
    ext = name.rsplit(".", 1)[-1].lower() if "." in name else "mp4"
    if ext not in ("mp4", "mov", "webm", "m4v"):
        ext = "mp4"
    filename = f"{uuid.uuid4()}.{ext}"
    os.makedirs(settings.OUTLET_VIDEOS_DIR, exist_ok=True)
    with open(os.path.join(settings.OUTLET_VIDEOS_DIR, filename), "wb") as f:
        f.write(content)

    public_url = f"{settings.BASE_URL}/uploads/outlet_videos/{filename}"
    outlet.video_url = public_url
    outlet.sync_status = "pending"
    outlet.synced_at = None
    await db.commit()
    return ok({"videoUrl": public_url})


@router.patch("/outlets/{outlet_id}/media")
async def update_outlet_media(
    outlet_id: str,
    body: OutletMediaPatch,
    current_outlet: str = Depends(get_current_outlet_id),
    db: AsyncSession = Depends(get_db),
):
    outlet = (await db.execute(select(Outlet).where(Outlet.id == outlet_id))).scalar_one_or_none()
    if outlet is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Outlet not found.")

    outlet.video_url = body.videoUrl
    outlet.sync_status = "pending"
    outlet.synced_at = None
    await db.commit()
    return ok({"videoUrl": outlet.video_url})
