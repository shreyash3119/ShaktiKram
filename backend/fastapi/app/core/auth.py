
"""Owner check using Supabase Auth and database ownership."""

from dataclasses import dataclass

import httpx
from fastapi import Depends, HTTPException
from fastapi.concurrency import run_in_threadpool
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy import text

from app.core.config import settings
from app.database.connection import engine


# Registers Bearer authentication in OpenAPI / Swagger.
bearer_scheme = HTTPBearer(auto_error=False)


@dataclass
class Owner:
    user_id: str
    token: str


async def verify_token(token: str) -> str:
    """Returns the Supabase user id for a valid access token."""

    if not settings.SUPABASE_URL:
        raise HTTPException(
            status_code=503,
            detail="Sign-in check is not configured"
        )

    async with httpx.AsyncClient(timeout=10) as client:
        r = await client.get(
            f"{settings.SUPABASE_URL}/auth/v1/user",
            headers={
                "Authorization": f"Bearer {token}",
                "apikey": settings.SUPABASE_PUBLISHABLE_KEY,
            },
        )

    if r.status_code != 200:
        raise HTTPException(
            status_code=401,
            detail="Invalid or expired session",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return r.json()["id"]


def is_owner(user_id: str) -> bool:
    with engine.connect() as conn:
        return conn.execute(
            text(
                "select 1 from app_owner "
                "where auth_user_id = cast(:u as uuid)"
            ),
            {"u": user_id},
        ).first() is not None


async def require_owner(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> Owner:

    if credentials is None:
        raise HTTPException(
            status_code=401,
            detail="Sign in required",
            headers={"WWW-Authenticate": "Bearer"},
        )

    token = credentials.credentials

    user_id = await verify_token(token)

    if not await run_in_threadpool(is_owner, user_id):
        raise HTTPException(
            status_code=403,
            detail="This account is not the owner"
        )

    return Owner(user_id=user_id, token=token)
