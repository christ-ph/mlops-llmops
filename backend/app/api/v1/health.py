"""GET /api/v1/health : état du service et de la base de données."""
from flask.views import MethodView
from flask_smorest import Blueprint
from marshmallow import Schema, fields
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from app.core.responses import success
from app.extensions import db

blp = Blueprint(
    "health", __name__, url_prefix="/api/v1/health", description="État du service"
)


class HealthDataSchema(Schema):
    status = fields.String()
    database = fields.String()


class HealthResponseSchema(Schema):
    data = fields.Nested(HealthDataSchema, allow_none=True)
    error = fields.Raw(allow_none=True)


@blp.route("")
class Health(MethodView):
    @blp.response(200, HealthResponseSchema)
    def get(self):
        """Vérifie l'API et la connexion PostgreSQL."""
        try:
            db.session.execute(text("SELECT 1"))
            db_up = True
        except SQLAlchemyError:
            db_up = False

        payload = success(
            {
                "status": "ok" if db_up else "degraded",
                "database": "up" if db_up else "down",
            }
        )
        return payload, (200 if db_up else 503)
