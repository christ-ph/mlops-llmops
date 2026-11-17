"""Configuration de l'application, par environnement."""
import os
from datetime import timedelta

from dotenv import load_dotenv

load_dotenv()


class Config:
    """Configuration commune."""

    SECRET_KEY = os.environ.get("SECRET_KEY", "dev-secret-change-me")
    JWT_SECRET_KEY = os.environ.get("JWT_SECRET_KEY", "dev-jwt-secret-change-me")
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(minutes=30)

    SQLALCHEMY_DATABASE_URI = os.environ.get(
        "DATABASE_URL",
        "postgresql+psycopg://modelops:modelops@localhost:5432/modelops",
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False

    CORS_ORIGINS = os.environ.get("CORS_ORIGINS", "http://localhost:5173").split(",")

    # Flask-Smorest / OpenAPI
    API_TITLE = "AI ModelOps Platform API"
    API_VERSION = "v1"
    OPENAPI_VERSION = "3.0.3"
    OPENAPI_URL_PREFIX = "/api"
    OPENAPI_JSON_PATH = "openapi.json"
    OPENAPI_SWAGGER_UI_PATH = "/docs"
    OPENAPI_SWAGGER_UI_URL = "https://cdn.jsdelivr.net/npm/swagger-ui-dist/"


class DevelopmentConfig(Config):
    DEBUG = True


class TestingConfig(Config):
    TESTING = True
    SQLALCHEMY_DATABASE_URI = "sqlite:///:memory:"
    SECRET_KEY = "test-secret"
    JWT_SECRET_KEY = "test-jwt-secret"


class ProductionConfig(Config):
    DEBUG = False

    @classmethod
    def validate(cls) -> None:
        """Refuse de démarrer avec des secrets par défaut."""
        for key in ("SECRET_KEY", "JWT_SECRET_KEY"):
            if not os.environ.get(key):
                raise RuntimeError(f"{key} doit être défini en production")


CONFIGS: dict[str, type[Config]] = {
    "development": DevelopmentConfig,
    "testing": TestingConfig,
    "production": ProductionConfig,
}


def get_config(name: str | None = None) -> type[Config]:
    """Retourne la classe de config selon `name` ou la variable APP_ENV."""
    env = name or os.environ.get("APP_ENV", "development")
    try:
        return CONFIGS[env]
    except KeyError as exc:
        raise ValueError(f"Environnement inconnu : {env}") from exc
