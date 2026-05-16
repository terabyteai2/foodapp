import os
import asyncio
from contextlib import asynccontextmanager
from pathlib import Path

import uvicorn
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from config import settings
from database import create_supabase_tables, create_tables
from network import local_base_url
from routers import admin, customer, devices, health, menu, orders, payments, sync, tenants, ws
from sync_worker import run_periodic_sync

FRONTEND_DIST = Path(__file__).parent / "frontend_dist"


def _start_ngrok() -> str | None:
    if not settings.NGROK_AUTHTOKEN or not settings.NGROK_STATIC_DOMAIN:
        return None
    try:
        from pyngrok import conf, ngrok
        conf.get_default().auth_token = settings.NGROK_AUTHTOKEN
        tunnel = ngrok.connect(
            addr=8000,
            proto="http",
            domain=settings.NGROK_STATIC_DOMAIN,
        )
        public_url: str = tunnel.public_url
        if public_url.startswith("http://"):
            public_url = "https://" + public_url[len("http://"):]
        return public_url
    except Exception as e:
        print(f"[ngrok] Failed to start tunnel: {e}")
        return None


@asynccontextmanager
async def lifespan(app: FastAPI):
    await create_tables()
    try:
        await create_supabase_tables()
    except Exception as error:
        print(f"[sync] Supabase table preparation skipped: {error}")
    os.makedirs(settings.IMAGES_DIR, exist_ok=True)
    os.makedirs(settings.OUTLET_IMAGES_DIR, exist_ok=True)
    os.makedirs(settings.OUTLET_VIDEOS_DIR, exist_ok=True)

    stop_sync = asyncio.Event()
    sync_task = asyncio.create_task(run_periodic_sync(stop_sync))

    public_url = _start_ngrok()
    if public_url:
        settings.BASE_URL = public_url
        print(f"\n  🌐 Public URL (ngrok):  {public_url}")
        print(f"  📋 API docs:            {public_url}/docs")
        print(f"  🍽️  Customer menu:       {public_url}/menu/YOUR_OUTLET_ID\n")
    else:
        settings.BASE_URL = local_base_url()
        print(f"\n  Local URL:      {settings.BASE_URL}")
        print(f"  API docs:       {settings.BASE_URL}/docs")
        print(f"  Customer menu:  {settings.BASE_URL}/menu\n")

    try:
        yield
    finally:
        stop_sync.set()
        sync_task.cancel()
        try:
            await sync_task
        except asyncio.CancelledError:
            pass


app = FastAPI(title="Rastarant POS API", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Static file mounts (uploads) ───────────────────────────────────────────────
os.makedirs("uploads", exist_ok=True)
app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")

# ── API Routers (registered before the SPA catch-all) ─────────────────────────
app.include_router(health.router)
app.include_router(tenants.router)
app.include_router(admin.router)
app.include_router(devices.router)
app.include_router(menu.router)
app.include_router(orders.router)
app.include_router(payments.router)
app.include_router(sync.router)
app.include_router(ws.router)
app.include_router(customer.router)


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    return JSONResponse(status_code=500, content={"error": str(exc)})


# ── React SPA — serves frontend_dist at /assets and catch-all for SPA routes ──
# Mount Vite's compiled assets (JS/CSS chunks) under /assets
if (FRONTEND_DIST / "assets").exists():
    app.mount("/assets", StaticFiles(directory=str(FRONTEND_DIST / "assets")), name="assets")


@app.get("/menu", include_in_schema=False)
async def serve_menu_root():
    """Serve the customer React SPA at the LAN QR URL."""
    index = FRONTEND_DIST / "index.html"
    if index.exists():
        return FileResponse(str(index))
    return JSONResponse(status_code=503, content={"error": "Customer menu not built yet. Run: bash build_frontend.sh"})


@app.get("/menu/{full_path:path}", include_in_schema=False)
async def serve_menu_spa(full_path: str):
    """Serve the customer React SPA for all /menu/* routes."""
    index = FRONTEND_DIST / "index.html"
    if index.exists():
        return FileResponse(str(index))
    return JSONResponse(status_code=503, content={"error": "Customer menu not built yet. Run: bash build_frontend.sh"})


@app.get("/", include_in_schema=False)
async def serve_root():
    """Redirect root to docs in dev; serve index.html if built."""
    index = FRONTEND_DIST / "index.html"
    if index.exists():
        return FileResponse(str(index))
    from fastapi.responses import RedirectResponse
    return RedirectResponse(url="/docs")


if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
