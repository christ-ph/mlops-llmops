"""Blueprints /api/v1/*."""
from flask_smorest import Api


def register_v1(api: Api) -> None:
    from app.api.v1.health import blp as health_blp
    from app.api.v1.predict import blp as predict_blp

    api.register_blueprint(health_blp)
    api.register_blueprint(predict_blp)