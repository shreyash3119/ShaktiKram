from fastapi import APIRouter, HTTPException
from sqlalchemy.exc import SQLAlchemyError

from app.database.connection import check_database_connection


router = APIRouter(tags=["Health"])


@router.get("/health")
def health_check():
    return {
        "status": "healthy",
        "application": "ShaktiKram API"
    }


@router.get("/health/database")
def database_health_check():
    try:
        result = check_database_connection()

        if result != 1:
            raise HTTPException(
                status_code=503,
                detail="Database connection failed"
            )

        return {
            "status": "connected",
            "database": "Supabase PostgreSQL",
            "query_test": "SELECT 1 successful"
        }

    except SQLAlchemyError:
        raise HTTPException(
            status_code=503,
            detail="Unable to connect to the database"
        )