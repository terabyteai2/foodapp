from datetime import datetime
from typing import Any

from pydantic import BaseModel


def ok(data: Any) -> dict:
    return {"data": data, "error": None}


def err(message: str) -> dict:
    return {"error": message}


# ── Tenants ──────────────────────────────────────────────────────────────────

class BootstrapRequest(BaseModel):
    serverId: str
    restaurantName: str
    outletName: str
    restaurantId: str | None = None
    outletId: str | None = None


class BootstrapResponse(BaseModel):
    serverId: str
    restaurantId: str
    outletId: str
    restaurantName: str
    outletName: str
    deviceToken: str


# ── Admin ─────────────────────────────────────────────────────────────────────

class AdminLoginRequest(BaseModel):
    usernameOrEmail: str
    password: str
    serverId: str


class AdminCreateRequest(BaseModel):
    outletId: str
    email: str
    username: str
    password: str


class GoogleTenantRequest(BaseModel):
    googleUid: str
    email: str
    displayName: str | None = None
    serverId: str
    restaurantName: str | None = None
    outletName: str | None = None
    restaurantId: str | None = None
    outletId: str | None = None


# ── Devices ───────────────────────────────────────────────────────────────────

class DeviceRegisterRequest(BaseModel):
    serverId: str
    restaurantId: str
    outletId: str
    restaurantName: str
    outletName: str


# ── Menu ──────────────────────────────────────────────────────────────────────

class MenuItemPayload(BaseModel):
    id: str
    name: str
    description: str | None = None
    price: float
    category: str | None = None
    isAvailable: bool = True
    imageUrl: str | None = None
    version: int = 1


class ImageUploadRequest(BaseModel):
    dataUrl: str
    fileName: str = "menu_image.jpg"


# ── Orders ────────────────────────────────────────────────────────────────────

class OrderPayload(BaseModel):
    id: str
    serialNumber: int = 0
    source: str = "pos"
    status: str = "pending"
    totalAmount: float = 0
    items: list[Any] = []
    notes: str | None = None
    createdAt: str | None = None
    updatedAt: str | None = None


class OrderStatusUpdate(BaseModel):
    status: str
    updatedAt: str | None = None


# ── BKash ─────────────────────────────────────────────────────────────────────

class BkashCreateRequest(BaseModel):
    serverId: str
    amount: float
    currency: str = "BDT"
    purpose: str = "admin_activation"
