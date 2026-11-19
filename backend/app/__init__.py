"""Application factory Flask."""
from flask import Flask, Response
from prometheus_client import CollectorRegistry, generate_latest, multiprocess
from prometheus_flask_exporter import PrometheusMetrics

from app.api import register_api
from app.config import ProductionConfig, get_config
from app.core.errors import register_error_handlers
from app.extensions import api, cors, db, jwt, migrate
from app.routes import register_routes

# Initialisation globale des métriques
metrics = PrometheusMetrics.for_app_factory()


def create_app(config_name: str | None = None) -> Flask:
    """Crée et configure l'application."""
    app = Flask(__name__)
    config_class = get_config(config_name)
    if config_class is ProductionConfig:
        ProductionConfig.validate()
    app.config.from_object(config_class)

    db.init_app(app)
    from app import models  # noqa: F401

    migrate.init_app(app, db)
    jwt.init_app(app)
    cors.init_app(app, resources={r"/api/*": {"origins": app.config["CORS_ORIGINS"]}})
    
    # Initialisation des métriques Flask
    metrics.init_app(app)

    api.init_app(app)
    register_api(api)
    register_routes(app)
    register_error_handlers(app)

    # Ajout manuel de la route /metrics avec un endpoint unique pour éviter le conflit
    @app.route("/metrics", endpoint="custom_prometheus_metrics")
    def prometheus_metrics():
        registry = CollectorRegistry()
        multiprocess.MultiProcessCollector(registry)
        data = generate_latest(registry)
        return Response(data, mimetype="text/plain")

    return app
