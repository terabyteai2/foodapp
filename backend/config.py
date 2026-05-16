from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Backward compatible: old DATABASE_URL now acts as the local database
    # fallback, while LOCAL_DATABASE_URL is the preferred offline-first setting.
    DATABASE_URL: str = "postgresql+asyncpg://postgres:password@localhost/rastarant"
    LOCAL_DATABASE_URL: str = ""
    SUPABASE_DATABASE_URL: str = ""
    SECRET_KEY: str = "change-me"
    IMAGES_DIR: str = "./uploads/menu_images"
    OUTLET_IMAGES_DIR: str = "./uploads/outlet_images"
    OUTLET_VIDEOS_DIR: str = "./uploads/outlet_videos"
    VIDEO_MAX_BYTES: int = 50 * 1024 * 1024  # 50 MB
    BASE_URL: str = "http://localhost:8000"
    LOCAL_SERVER_IP: str = ""
    SYNC_INTERVAL_SECONDS: int = 30
    SYNC_BATCH_SIZE: int = 100
    CREATE_SUPABASE_TABLES: bool = True

    NGROK_AUTHTOKEN: str = ""
    NGROK_STATIC_DOMAIN: str = ""

    @property
    def local_database_url(self) -> str:
        return self.LOCAL_DATABASE_URL.strip() or self.DATABASE_URL

    @property
    def supabase_database_url(self) -> str:
        return self.SUPABASE_DATABASE_URL.strip()

    @property
    def has_supabase_database(self) -> bool:
        return bool(self.supabase_database_url)


settings = Settings()
