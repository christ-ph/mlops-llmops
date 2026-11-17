"""Application factory Flask."""
from flask import Flask

from app.api import register_api
from app.config import ProductionConfig, get_config
from app.core.errors import register_error_handlers
from app.extensions import api, cors, db, jwt, migrate
from app.routes import register_routes


def create_app(config_name: str | None = None) -> Flask:
    """Crée et configure l'application."""
    app = Flask(__name__)
    config_class = get_config(config_name)
    if config_class is ProductionConfig:
        ProductionConfig.validate()
    app.config.from_object(config_class)

    db.init_app(app)
    # Import des modèles pour qu'Alembic les voie
    from app import models  # noqa: F401

    migrate.init_app(app, db)
    jwt.init_app(app)
    cors.init_app(app, resources={r"/api/*": {"origins": app.config["CORS_ORIGINS"]}})
    api.init_app(app)

    register_api(api)
    register_routes(app)
    # Après api.init_app pour surcharger le handler HTTP de smorest
    register_error_handlers(app)

    return app
