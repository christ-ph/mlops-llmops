"""API versionnée /api/v1/*."""
from flask_smorest import Api


def register_api(api: Api) -> None:
    from app.api.v1 import register_v1

    register_v1(api)
