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
