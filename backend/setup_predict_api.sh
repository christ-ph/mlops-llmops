#!/usr/bin/env bash
# backend/setup_predict_api.sh
# Crée les fichiers de l'API /api/v1/predict (étape 5).
#
# Idempotent : ne remplace pas les fichiers existants (sauf app/api/v1/__init__.py
# qui est patché, avec backup .bak).
# Usage :
#   cd backend && bash setup_predict_api.sh
#   cd backend && bash setup_predict_api.sh --force
set -euo pipefail

FORCE=0
for arg in "$@"; do
  case "$arg" in
    -f|--force) FORCE=1 ;;
    *) echo "Argument inconnu : $arg" >&2; exit 1 ;;
  esac
done

BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$BACKEND_DIR")"

if [ ! -d "$BACKEND_DIR/app" ] || [ ! -d "$BACKEND_DIR/mlops" ]; then
  echo "✖ Place ce script dans backend/ puis relance-le." >&2
  exit 1
fi

write_file() {
  local path="$1"
  local existed=0
  [ -e "$path" ] && existed=1

  if [ "$existed" -eq 1 ] && [ "$FORCE" -ne 1 ]; then
    echo "⏭  existe déjà : ${path#"$ROOT_DIR"/}"
    cat >/dev/null
    return
  fi

  mkdir -p "$(dirname "$path")"
  cat >"$path"
  if [ "$existed" -eq 1 ]; then
    echo "✔  mis à jour  : ${path#"$ROOT_DIR"/}"
  else
    echo "✔  créé        : ${path#"$ROOT_DIR"/}"
  fi
}

# ---------------------------------------------------------------- predictor
write_file "$BACKEND_DIR/mlops/registry/predictor.py" <<'PYEOF'
"""Chargement et prédiction du modèle champion (cache en mémoire).

Le modèle champion est chargé une seule fois depuis MLflow (alias `champion`)
et gardé en mémoire. Les requêtes suivantes réutilisent l'objet via un cache
thread-safe, ce qui réduit la latence de ~500 ms à ~5 ms par prédiction.
"""
from __future__ import annotations

import threading
from typing import Any

import pandas as pd

from mlops.config import CHAMPION_ALIAS, REGISTERED_MODEL_NAME, TRACKING_URI

_lock = threading.Lock()
_cached_model: Any | None = None


def _ensure_tracking() -> None:
    """Configure MLflow tracking (idempotent)."""
    import mlflow

    mlflow.set_tracking_uri(TRACKING_URI)


def reset_cache() -> None:
    """Vide le cache (utile pour les tests ou après une promotion)."""
    global _cached_model
    with _lock:
        _cached_model = None


def get_champion(
    model_name: str = REGISTERED_MODEL_NAME,
    alias: str = CHAMPION_ALIAS,
):
    """Retourne le modèle champion (chargé une fois puis caché)."""
    global _cached_model
    with _lock:
        if _cached_model is None:
            _ensure_tracking()
            from mlops.registry.registry import load_champion_model

            _cached_model = load_champion_model(model_name, alias)
    return _cached_model


def get_champion_metadata(
    model_name: str = REGISTERED_MODEL_NAME,
    alias: str = CHAMPION_ALIAS,
) -> dict[str, Any]:
    """Métadonnées publiques du champion (nom, alias, version, métriques, features)."""
    _ensure_tracking()
    from mlflow import MlflowClient
    from mlflow.models import Model

    client = MlflowClient()
    mv = client.get_model_version_by_alias(model_name, alias)
    run = client.get_run(mv.run_id)

    mlflow_model = Model.load(f"runs:/{mv.run_id}/model")
    signature = mlflow_model.signature
    features: list[str] = []
    if signature is not None and signature.inputs is not None:
        features = [col.name for col in signature.inputs]

    return {
        "model_name": model_name,
        "alias": alias,
        "version": mv.version,
        "metrics": dict(run.data.metrics),
        "features": features,
    }


def _extract_raw_model(model: Any) -> Any:
    """Déballe le wrapper MLflow pyfunc pour atteindre le modèle sklearn sous-jacent."""
    return getattr(model, "_model_impl", model)


def predict_records(records: list[dict[str, Any]]) -> dict[str, Any]:
    """Prédit sur une liste de dicts (features brutes).

    Retourne :
      - ``predictions`` : liste d'entiers (0/1 pour une classification binaire)
      - ``probabilities`` : liste de listes (une ligne par record), si le modèle
        expose ``predict_proba``.
    """
    model = get_champion()
    df = pd.DataFrame(records)
    predictions = model.predict(df)

    result: dict[str, Any] = {"predictions": [int(p) for p in predictions]}

    raw = _extract_raw_model(model)
    if hasattr(raw, "predict_proba"):
        proba = raw.predict_proba(df)
        result["probabilities"] = proba.tolist()

    return result
PYEOF

# ----------------------------------------------------------------- predict
write_file "$BACKEND_DIR/app/api/v1/predict.py" <<'PYEOF'
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
PYEOF

# ------------------------------------------------------------------- tests
write_file "$BACKEND_DIR/tests/test_predict_api.py" <<'PYEOF'
"""Tests de l'API /api/v1/predict (modèle champion mocké)."""
from unittest.mock import MagicMock

import numpy as np
import pytest

from mlops.registry import predictor


@pytest.fixture()
def fake_model():
    model = MagicMock()
    model.predict.return_value = np.array([1, 0, 1])
    model.predict_proba.return_value = np.array(
        [[0.1, 0.9], [0.8, 0.2], [0.3, 0.7]]
    )
    return model


@pytest.fixture()
def fake_metadata():
    return {
        "model_name": "breast-cancer-classifier",
        "alias": "champion",
        "version": "1",
        "metrics": {"test_f1": 0.9861, "test_accuracy": 0.98},
        "features": ["mean radius", "mean texture"],
    }


@pytest.fixture()
def patched(monkeypatch, fake_model, fake_metadata):
    monkeypatch.setattr(predictor, "_cached_model", fake_model)
    monkeypatch.setattr(predictor, "get_champion_metadata", lambda: fake_metadata)


def test_metadata(client, patched):
    resp = client.get("/api/v1/predict/metadata")
    assert resp.status_code == 200
    body = resp.get_json()
    assert body["model_name"] == "breast-cancer-classifier"
    assert body["alias"] == "champion"
    assert body["version"] == "1"
    assert "test_f1" in body["metrics"]
    assert isinstance(body["features"], list)


def test_predict_one(client, patched):
    resp = client.post(
        "/api/v1/predict",
        json={"records": [{"mean radius": 17.99, "mean texture": 10.38}]},
    )
    assert resp.status_code == 200
    body = resp.get_json()
    assert len(body["predictions"]) == 1
    assert body["predictions"][0] in (0, 1)
    assert len(body["probabilities"][0]) == 2
    assert abs(sum(body["probabilities"][0]) - 1.0) < 1e-6


def test_predict_many(client, patched):
    resp = client.post(
        "/api/v1/predict",
        json={
            "records": [
                {"mean radius": 17.99, "mean texture": 10.38},
                {"mean radius": 12.50, "mean texture": 18.20},
                {"mean radius": 20.10, "mean texture": 22.70},
            ]
        },
    )
    assert resp.status_code == 200
    body = resp.get_json()
    assert len(body["predictions"]) == 3
    assert len(body["probabilities"]) == 3


def test_predict_empty_records(client, patched):
    resp = client.post("/api/v1/predict", json={"records": []})
    assert resp.status_code == 400
    assert "records" in resp.get_json()["message"].lower()


def test_predict_missing_field(client, patched):
    resp = client.post("/api/v1/predict", json={})
    assert resp.status_code == 422


def test_predict_malformed_records(client, patched):
    resp = client.post("/api/v1/predict", json={"records": ["pas un dict"]})
    assert resp.status_code == 422
PYEOF

# ------------------------------------------------- patch app/api/v1/__init__
INIT_FILE="$BACKEND_DIR/app/api/v1/__init__.py"
if [ ! -f "$INIT_FILE" ]; then
  echo "✖ $INIT_FILE introuvable — crée-le manuellement puis relance." >&2
  exit 1
fi

cp "$INIT_FILE" "$INIT_FILE.bak"
echo "✔  backup      : app/api/v1/__init__.py.bak"

python3 - "$INIT_FILE" <<'PYEOF'
import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text(encoding="utf-8")

if "predict_blp" in src:
    print("⏭  app/api/v1/__init__.py contient déjà predict_blp — rien à faire")
    sys.exit(0)

import_line = "    from app.api.v1.health import blp as health_blp"
new_import_line = import_line + "\n    from app.api.v1.predict import blp as predict_blp"

register_line = "    api.register_blueprint(health_blp)"
new_register_line = register_line + "\n    api.register_blueprint(predict_blp)"

if import_line not in src:
    print("⚠  Ligne d'import health_blp introuvable. Ajoute manuellement :", file=sys.stderr)
    print("   from app.api.v1.predict import blp as predict_blp", file=sys.stderr)
    sys.exit(1)

if register_line not in src:
    print("⚠  Ligne register_blueprint(health_blp) introuvable. Ajoute manuellement :", file=sys.stderr)
    print("   api.register_blueprint(predict_blp)", file=sys.stderr)
    sys.exit(1)

src = src.replace(import_line, new_import_line, 1)
src = src.replace(register_line, new_register_line, 1)
path.write_text(src, encoding="utf-8")
print("✔  patché      : app/api/v1/__init__.py (backup: .bak)")
PYEOF

cat <<'EOF'

Terminé.

Suite (depuis backend/) :

  uv run pytest tests/test_predict_api.py -v
  uv run pytest tests/ -v

Puis test manuel (2 terminaux) :

  uv run flask --app app run --port 5000
  curl -s http://localhost:5000/api/v1/predict/metadata | python -m json.tool
  curl -s -X POST http://localhost:5000/api/v1/predict \
    -H "Content-Type: application/json" \
    -d '{"records": [{"mean radius": 17.99, "mean texture": 10.38}]}' \
    | python -m json.tool

Swagger UI : http://localhost:5000/api/docs
EOF
