"""Blueprints simples (hors API versionnée)."""
from flask import Flask


def register_routes(app: Flask) -> None:
    from app.routes.health import bp as health_bp

    app.register_blueprint(health_bp)
