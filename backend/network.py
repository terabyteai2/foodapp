import socket

from config import settings


def get_lan_ip() -> str:
    configured = settings.LOCAL_SERVER_IP.strip()
    if configured:
        return configured
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))
        return sock.getsockname()[0]
    except Exception:
        return "127.0.0.1"
    finally:
        sock.close()


def local_base_url() -> str:
    return f"http://{get_lan_ip()}:8000"
