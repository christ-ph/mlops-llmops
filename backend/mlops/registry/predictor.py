"""Chargement et prédiction du modèle champion (cache en mémoire)."""
from __future__ import annotations

import threading
import time
from typing import Any

import pandas as pd

from app.monitoring import (
    MODEL_LOADED,
    PREDICTION_BATCH_SIZE,
    PREDICTION_COUNTER,
    PREDICTION_DISTRIBUTION,
    PREDICTION_LATENCY,
)
from mlops.config import CHAMPION_ALIAS, REGISTERED_MODEL_NAME, TRACKING_URI

_lock = threading.Lock()
_cached_model: Any | None = None


def _ensure_tracking() -> None:
    import mlflow
    mlflow.set_tracking_uri(TRACKING_URI)


def reset_cache() -> None:
    global _cached_model
    with _lock:
        _cached_model = None
        MODEL_LOADED.set(0)


def get_champion(
    model_name: str = REGISTERED_MODEL_NAME,
    alias: str = CHAMPION_ALIAS,
):
    global _cached_model
    with _lock:
        if _cached_model is None:
            _ensure_tracking()
            from mlops.registry.registry import load_champion_model
            _cached_model = load_champion_model(model_name, alias)
            MODEL_LOADED.set(1)
    return _cached_model


def get_champion_metadata(
    model_name: str = REGISTERED_MODEL_NAME,
    alias: str = CHAMPION_ALIAS,
) -> dict[str, Any]:
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
    return getattr(model, "_model_impl", model)


def predict_records(records: list[dict[str, Any]]) -> dict[str, Any]:
    """Prédit sur une liste de dicts (features brutes) avec instrumentation Prometheus."""
    model_name = REGISTERED_MODEL_NAME
    model = get_champion()

    df = pd.DataFrame(records)
    PREDICTION_BATCH_SIZE.observe(len(df))

    start = time.perf_counter()
    predictions = model.predict(df)
    elapsed = time.perf_counter() - start
    PREDICTION_LATENCY.labels(model_name=model_name).observe(elapsed)

    pred_list = [int(p) for p in predictions]
    for p in pred_list:
        PREDICTION_COUNTER.labels(model_name=model_name, model_version="champion").inc()
        PREDICTION_DISTRIBUTION.labels(model_name=model_name, predicted_class=str(p)).inc()

    result: dict[str, Any] = {"predictions": pred_list}

    raw = _extract_raw_model(model)
    if hasattr(raw, "predict_proba"):
        proba = raw.predict_proba(df)
        result["probabilities"] = proba.tolist()

    return result
