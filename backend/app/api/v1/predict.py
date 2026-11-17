"""Endpoints de prédiction basés sur le modèle champion MLflow."""
from __future__ import annotations

from flask.views import MethodView
from flask_smorest import Blueprint, abort
from marshmallow import Schema, fields

from mlops.registry import predictor

blp = Blueprint(
    "predict",
    __name__,
    url_prefix="/api/v1/predict",
    description="Prédictions avec le modèle champion",
)


class PredictionInputSchema(Schema):
    """Corps d'entrée : une liste d'objets {feature: valeur}."""

    records = fields.List(
        fields.Dict(keys=fields.String(), values=fields.Raw()),
        required=True,
    )


class PredictionOutputSchema(Schema):
    predictions = fields.List(fields.Integer(), required=True)
    probabilities = fields.List(fields.List(fields.Float()), required=False)


class MetadataOutputSchema(Schema):
    model_name = fields.String(required=True)
    alias = fields.String(required=True)
    version = fields.String(required=True)
    metrics = fields.Dict(required=True)
    features = fields.List(fields.String(), required=True)


@blp.route("/metadata")
class Metadata(MethodView):
    @blp.response(200, MetadataOutputSchema)
    def get(self):
        """Retourne les informations du modèle champion."""
        return predictor.get_champion_metadata()


@blp.route("")
class Predict(MethodView):
    @blp.arguments(PredictionInputSchema)
    @blp.response(200, PredictionOutputSchema)
    def post(self, payload):
        """Prédit sur une liste de records (features brutes)."""
        records = payload.get("records", [])
        if not records:
            abort(400, message="'records' ne peut pas être vide")
        try:
            return predictor.predict_records(records)
        except Exception as exc:  # noqa: BLE001
            abort(500, message=f"Erreur de prédiction : {exc}")
