"""MLflow : configuration, enregistrement et promotion des modèles."""
from __future__ import annotations

from pathlib import Path

import mlflow
from mlflow import MlflowClient
from mlflow.exceptions import MlflowException

from mlops.config import (
    ARTIFACT_ROOT,
    CHAMPION_ALIAS,
    EXPERIMENT_NAME,
    PRIMARY_METRIC,
    REGISTERED_MODEL_NAME,
    TRACKING_URI,
)


def configure_mlflow(
    tracking_uri: str = TRACKING_URI,
    artifact_root: Path | str = ARTIFACT_ROOT,
    experiment_name: str = EXPERIMENT_NAME,
) -> str:
    """Configure le tracking, crée l'expérience si besoin, retourne son id."""
    prefix = "sqlite:///"
    if tracking_uri.startswith(prefix):
        Path(tracking_uri[len(prefix):]).parent.mkdir(parents=True, exist_ok=True)
    artifact_root = Path(artifact_root).resolve()
    artifact_root.mkdir(parents=True, exist_ok=True)

    mlflow.set_tracking_uri(tracking_uri)
    client = MlflowClient()
    experiment = client.get_experiment_by_name(experiment_name)
    if experiment is None:
        experiment_id = client.create_experiment(
            experiment_name, artifact_location=artifact_root.as_uri()
        )
    else:
        experiment_id = experiment.experiment_id
    mlflow.set_experiment(experiment_id=experiment_id)
    return experiment_id


def register_model(model_uri: str, model_name: str = REGISTERED_MODEL_NAME) -> str:
    """Enregistre un modèle dans le registry.

    Accepte une URI complète `models:/...` ou `runs:/.../model`,
    ou un run_id brut (compatibilité) → converti en `runs:/<run_id>/model`.
    """
    if not model_uri.startswith(("runs:/", "models:/")):
        model_uri = f"runs:/{model_uri}/model"
    result = mlflow.register_model(model_uri, model_name)
    return str(result.version)


def _score(client: MlflowClient, run_id: str, metric: str) -> float | None:
    return client.get_run(run_id).data.metrics.get(metric)


def promote_if_better(
    model_name: str,
    version: str,
    metric: str = PRIMARY_METRIC,
    alias: str = CHAMPION_ALIAS,
) -> bool:
    """Donne l'alias `champion` à la version si elle bat le champion actuel."""
    client = MlflowClient()
    new_run_id = client.get_model_version(model_name, version).run_id
    new_score = _score(client, new_run_id, metric)
    if new_score is None:
        raise ValueError(f"Métrique {metric!r} absente du run {new_run_id}")

    try:
        champion = client.get_model_version_by_alias(model_name, alias)
    except MlflowException:
        champion = None

    if champion is not None:
        champion_score = _score(client, champion.run_id, metric)
        if champion_score is not None and new_score <= champion_score:
            return False

    client.set_registered_model_alias(model_name, alias, version)
    return True


def load_champion_model(
    model_name: str = REGISTERED_MODEL_NAME, alias: str = CHAMPION_ALIAS
):
    """Charge le modèle champion (utilisé plus tard par l'API de prédiction)."""
    return mlflow.pyfunc.load_model(f"models:/{model_name}@{alias}")
