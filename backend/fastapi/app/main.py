from fastapi import FastAPI

from app.core.config import settings
from app.api.routes import health


# Interactive docs and the schema are for development only.
app = FastAPI(
    title=settings.APP_NAME,
    description="Personal Fitness Management System API",
    version="1.0.0",
    debug=settings.DEBUG,
    docs_url=None if settings.is_production else "/docs",
    redoc_url=None if settings.is_production else "/redoc",
    openapi_url=None if settings.is_production else "/openapi.json",
)


app.include_router(
    health.router,
    prefix="/api/v1"
)


@app.get("/")
def root():
    return {
        "message": "Welcome to ShaktiKram API",
        "environment": settings.APP_ENV,
        "docs": None if settings.is_production else "/docs"
    }
