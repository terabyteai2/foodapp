from datetime import datetime, timezone
import uuid

import httpx
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from auth import create_device_token, hash_password, verify_password
from config import settings
from database import get_db
from models import AdminAccount, Outlet, Restaurant
from schemas import AdminCreateRequest, AdminLoginRequest, GoogleTenantRequest, ok

router = APIRouter()


def _tenant_response(
    *,
    server_id: str,
    restaurant: Restaurant,
    outlet: Outlet,
    account: AdminAccount,
) -> dict:
    return {
        "serverId": server_id,
        "restaurantId": restaurant.id,
        "outletId": outlet.id,
        "restaurantName": restaurant.name,
        "outletName": outlet.name,
        "deviceToken": create_device_token(outlet.id),
        "account": {
            "email": account.email,
            "username": account.username,
        },
    }


@router.post("/admin/login")
async def admin_login(body: AdminLoginRequest, db: AsyncSession = Depends(get_db)):
    outlet = (await db.execute(select(Outlet).where(Outlet.server_id == body.serverId))).scalar_one_or_none()
    if outlet is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Server ID not registered.")

    account = (
        await db.execute(
            select(AdminAccount).where(
                (AdminAccount.outlet_id == outlet.id)
                & (
                    (AdminAccount.email == body.usernameOrEmail.strip())
                    | (AdminAccount.username == body.usernameOrEmail.strip())
                )
            )
        )
    ).scalar_one_or_none()

    if account is None or not verify_password(body.password, account.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials.")

    restaurant = (await db.execute(select(Restaurant).where(Restaurant.id == outlet.restaurant_id))).scalar_one()
    return ok(
        _tenant_response(
            server_id=body.serverId,
            restaurant=restaurant,
            outlet=outlet,
            account=account,
        )
    )


@router.post("/admin/google")
async def google_tenant(
    body: GoogleTenantRequest,
    db: AsyncSession = Depends(get_db),
):
    email = body.email.strip().lower()
    google_uid = body.googleUid.strip()
    if not email or not google_uid:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Google account is incomplete.")

    account = (
        await db.execute(
            select(AdminAccount).where(
                (AdminAccount.google_uid == google_uid) | (AdminAccount.email == email)
            )
        )
    ).scalar_one_or_none()
    if account is None:
        account = await _import_google_account_from_supabase(email=email, google_uid=google_uid, db=db)

    if account is None and body.restaurantName and body.outletName:
        account = await _create_google_tenant(body=body, email=email, google_uid=google_uid, db=db)

    if account is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No restaurant is linked to this Google account yet.",
        )

    if account.google_uid != google_uid:
        account.google_uid = google_uid
        await db.commit()

    outlet = (await db.execute(select(Outlet).where(Outlet.id == account.outlet_id))).scalar_one()
    restaurant = (await db.execute(select(Restaurant).where(Restaurant.id == outlet.restaurant_id))).scalar_one()

    return ok(
        _tenant_response(
            server_id=outlet.server_id or body.serverId,
            restaurant=restaurant,
            outlet=outlet,
            account=account,
        )
    )


@router.post("/admin/create")
async def create_admin(body: AdminCreateRequest, db: AsyncSession = Depends(get_db)):
    outlet = (await db.execute(select(Outlet).where(Outlet.id == body.outletId))).scalar_one_or_none()
    if outlet is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Outlet not found.")

    existing = (
        await db.execute(
            select(AdminAccount).where(
                (AdminAccount.email == body.email) | (AdminAccount.username == body.username)
            )
        )
    ).scalar_one_or_none()
    if existing:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Email or username already in use.")

    account = AdminAccount(
        restaurant_id=outlet.restaurant_id,
        outlet_id=body.outletId,
        email=body.email,
        username=body.username,
        password_salt="local",
        password_hash=hash_password(body.password),
    )
    db.add(account)
    await db.commit()
    return ok({"created": True, "username": body.username, "email": body.email})


async def _create_google_tenant(
    *,
    body: GoogleTenantRequest,
    email: str,
    google_uid: str,
    db: AsyncSession,
) -> AdminAccount:
    restaurant_id = body.restaurantId or str(uuid.uuid4())
    outlet_id = body.outletId or str(uuid.uuid4())
    restaurant = Restaurant(id=restaurant_id, name=body.restaurantName.strip())
    outlet = Outlet(
        id=outlet_id,
        restaurant_id=restaurant.id,
        name=body.outletName.strip(),
        server_id=body.serverId,
    )
    account = AdminAccount(
        restaurant_id=restaurant.id,
        outlet_id=outlet.id,
        email=email,
        username=_username_from_google(email=email, display_name=body.displayName),
        google_uid=google_uid,
        password_salt="google",
        password_hash=f"google:{google_uid}",
        role="owner",
        is_active=True,
    )
    db.add_all([restaurant, outlet, account])
    await db.commit()
    await _push_google_account_to_supabase(restaurant=restaurant, outlet=outlet, account=account)
    return account


async def _import_google_account_from_supabase(
    *,
    email: str,
    google_uid: str,
    db: AsyncSession,
) -> AdminAccount | None:
    if not settings.has_supabase_rest:
        return None
    headers = _supabase_headers()
    async with httpx.AsyncClient(timeout=20) as client:
        account_response = await client.get(
            f"{settings.supabase_rest_url}/admin_accounts",
            headers=headers,
            params={"email": f"eq.{email}", "select": "*", "limit": "1"},
        )
        if account_response.status_code >= 400:
            return None
        rows = account_response.json()
        if not rows:
            return None
        row = rows[0]
        outlet_id = row.get("outlet_id")
        restaurant_id = row.get("restaurant_id")
        if not outlet_id or not restaurant_id:
            return None
        restaurant_response = await client.get(
            f"{settings.supabase_rest_url}/restaurants",
            headers=headers,
            params={"id": f"eq.{restaurant_id}", "select": "*", "limit": "1"},
        )
        outlet_response = await client.get(
            f"{settings.supabase_rest_url}/outlets",
            headers=headers,
            params={"id": f"eq.{outlet_id}", "select": "*", "limit": "1"},
        )
    if restaurant_response.status_code >= 400 or outlet_response.status_code >= 400:
        return None
    restaurant_rows = restaurant_response.json()
    outlet_rows = outlet_response.json()
    if not restaurant_rows or not outlet_rows:
        return None

    restaurant_row = restaurant_rows[0]
    outlet_row = outlet_rows[0]
    restaurant = Restaurant(
        id=restaurant_id,
        name=restaurant_row.get("name") or "Restaurant",
        sync_status="synced",
    )
    outlet = Outlet(
        id=outlet_id,
        restaurant_id=restaurant_id,
        name=outlet_row.get("name") or "Main Outlet",
        server_id=outlet_row.get("server_id") or str(uuid.uuid4()),
        sync_status="synced",
    )
    account = AdminAccount(
        id=row.get("id") or str(uuid.uuid4()),
        restaurant_id=restaurant_id,
        outlet_id=outlet_id,
        email=email,
        username=row.get("username") or _username_from_google(email=email, display_name=None),
        google_uid=google_uid,
        password_salt=row.get("password_salt") or "google",
        password_hash=row.get("password_hash") or f"google:{google_uid}",
        role=row.get("role") or "owner",
        is_active=row.get("is_active") is not False,
        sync_status="synced",
    )
    await db.merge(restaurant)
    await db.merge(outlet)
    await db.merge(account)
    await db.commit()
    return account


async def _push_google_account_to_supabase(
    *,
    restaurant: Restaurant,
    outlet: Outlet,
    account: AdminAccount,
) -> None:
    if not settings.has_supabase_rest:
        return
    now = datetime.now(timezone.utc).isoformat()
    headers = _supabase_headers()
    headers["Prefer"] = "resolution=merge-duplicates,return=minimal"
    async with httpx.AsyncClient(timeout=20) as client:
        for table, payload in (
            (
                "restaurants",
                {
                    "id": restaurant.id,
                    "name": restaurant.name,
                    "created_at": now,
                    "updated_at": now,
                },
            ),
            (
                "outlets",
                {
                    "id": outlet.id,
                    "restaurant_id": restaurant.id,
                    "name": outlet.name,
                    "created_at": now,
                    "updated_at": now,
                },
            ),
            (
                "admin_accounts",
                {
                    "id": account.id,
                    "restaurant_id": restaurant.id,
                    "outlet_id": outlet.id,
                    "email": account.email,
                    "username": account.username,
                    "password_salt": account.password_salt,
                    "password_hash": account.password_hash,
                    "role": account.role,
                    "is_active": account.is_active,
                    "created_at": now,
                    "updated_at": now,
                },
            ),
        ):
            response = await client.post(
                f"{settings.supabase_rest_url}/{table}",
                headers=headers,
                params={"on_conflict": "id"},
                json=[payload],
            )
            if response.status_code not in {200, 201, 204}:
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail=f"Could not link Google account in cloud: {response.text}",
                )


def _username_from_google(*, email: str, display_name: str | None) -> str:
    candidate = (display_name or email.split("@", 1)[0]).strip().lower()
    cleaned = "".join(ch if ch.isalnum() else "_" for ch in candidate).strip("_")
    return cleaned or f"user_{uuid.uuid4().hex[:8]}"


def _supabase_headers() -> dict[str, str]:
    key = settings.supabase_service_role_key
    return {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
