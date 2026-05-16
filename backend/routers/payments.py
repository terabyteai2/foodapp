import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models import BkashSession
from schemas import BkashCreateRequest, ok

router = APIRouter()


def _session_dict(s: BkashSession) -> dict:
    return {
        "paymentId": s.id,
        "serverId": s.server_id,
        "amount": float(s.amount),
        "currency": s.currency,
        "purpose": s.purpose,
        "status": s.status,
        "localId": s.local_id,
        "remoteId": s.remote_id,
        "syncStatus": s.sync_status,
        "lastSyncError": s.last_sync_error,
        "createdAt": s.created_at.isoformat(),
        "updatedAt": s.updated_at.isoformat(),
        "syncedAt": s.synced_at.isoformat() if s.synced_at else None,
    }


@router.post("/payments/bkash/create")
async def create_bkash_payment(body: BkashCreateRequest, db: AsyncSession = Depends(get_db)):
    session = BkashSession(
        id=str(uuid.uuid4()),
        server_id=body.serverId,
        amount=body.amount,
        currency=body.currency,
        purpose=body.purpose,
        status="pending",
    )
    db.add(session)
    await db.commit()
    await db.refresh(session)
    return ok(_session_dict(session))


@router.post("/payments/bkash/{payment_id}/verify")
async def verify_bkash_payment(payment_id: str, db: AsyncSession = Depends(get_db)):
    session = (await db.execute(select(BkashSession).where(BkashSession.id == payment_id))).scalar_one_or_none()
    if session is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Payment not found.")
    session.status = "verified"
    session.sync_status = "pending"
    session.synced_at = None
    await db.commit()
    await db.refresh(session)
    return ok(_session_dict(session))


@router.get("/payments/bkash/{payment_id}/status")
async def bkash_payment_status(payment_id: str, db: AsyncSession = Depends(get_db)):
    session = (await db.execute(select(BkashSession).where(BkashSession.id == payment_id))).scalar_one_or_none()
    if session is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Payment not found.")
    return ok(_session_dict(session))
