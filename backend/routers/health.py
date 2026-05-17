from fastapi import APIRouter
from database import check_local_database, check_supabase_database
from network import local_base_url
from schemas import ok
from sync_worker import check_supabase_rest, internet_available, sync_status

router = APIRouter()


@router.get("/health")
async def health():
    sync = await sync_status()
    base_url = local_base_url()
    return ok({
        "status": "ok",
        "localDatabase": sync["localDatabase"],
        "internet": sync["internet"],
        "supabaseDatabase": sync["supabaseDatabase"],
        "sync": {
            "configured": sync["configured"],
            "pending": sync["pending"],
            "syncing": sync["syncing"],
            "synced": sync["synced"],
            "failed": sync["failed"],
            "lastSyncAt": sync["lastSyncAt"],
            "lastError": sync["lastError"],
        },
        "lan": {
            "baseUrl": base_url,
            "menuUrl": f"{base_url}/menu",
        },
        "realtime": {
            "enabled": False,
            "supabaseUrl": "",
            "publishableKey": "",
            "channelPrefix": "pos:outlet:",
        },
    })


@router.get("/health/local-database")
async def local_database_health():
    return ok({"connected": await check_local_database()})


@router.get("/health/internet")
async def internet_health():
    return ok({"connected": await internet_available()})


@router.get("/health/supabase")
async def supabase_health():
    return ok({
        "connected": await check_supabase_database() or await check_supabase_rest()
    })


@router.get("/health/sync")
async def sync_health():
    return ok(await sync_status())
