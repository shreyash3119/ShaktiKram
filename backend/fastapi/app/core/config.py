from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    APP_NAME: str = "ShaktiKram API"
    APP_ENV: str = "development"
    # Off unless asked for: DEBUG makes SQLAlchemy log every statement together with its parameters (health data).
    DEBUG: bool = False

    DATABASE_URL: str

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore"
    )

    @property
    def is_production(self) -> bool:
        return self.APP_ENV.lower() == "production"


settings = Settings()
