from fastapi import APIRouter

from schemas import ok
from sync_worker import sync_once, sync_status

router = APIRouter(prefix="/sync", tags=["sync"])


@router.get("/status")
async def get_sync_status():
    return ok(await sync_status())


@router.post("/now")
async def run_sync_now():
    return ok(await sync_once())
