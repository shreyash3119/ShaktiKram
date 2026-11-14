from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    APP_NAME: str = "ShaktiKram API"
    APP_ENV: str = "development"
    # Off unless asked for: DEBUG makes SQLAlchemy log every statement together with its parameters (health data).
    DEBUG: bool = False

    # Use the read-only role (pfs_reader), never the owner role: this service only reads.
    DATABASE_URL: str

    # Sign-in check: the app sends the owner's Supabase access token; this service asks Supabase Auth whether it is valid.
    SUPABASE_URL: str = ""
    SUPABASE_PUBLISHABLE_KEY: str = ""
    # Folder holding shared/vocabulary. Empty means the repository's own shared folder.
    SHARED_DIR: str = ""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore"
    )

    @property
    def is_production(self) -> bool:
        return self.APP_ENV.lower() == "production"


settings = Settings()
