"""Construction et entraînement des modèles scikit-learn."""
from __future__ import annotations

from typing import Any

import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import GradientBoostingClassifier, RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline

from mlops.config import RANDOM_SEED

MODEL_REGISTRY: dict[str, type] = {
    "logistic_regression": LogisticRegression,
    "random_forest": RandomForestClassifier,
    "gradient_boosting": GradientBoostingClassifier,
}

DEFAULT_PARAMS: dict[str, dict[str, Any]] = {
    "logistic_regression": {"max_iter": 1000},
    "random_forest": {"n_estimators": 200, "random_state": RANDOM_SEED, "n_jobs": -1},
    "gradient_boosting": {"random_state": RANDOM_SEED},
}


def build_pipeline(
    model_name: str,
    preprocessor: ColumnTransformer,
    params: dict[str, Any] | None = None,
) -> Pipeline:
    """Pipeline complet (préprocesseur + modèle) : le modèle enregistré accepte des données brutes."""
    if model_name not in MODEL_REGISTRY:
        raise ValueError(
            f"Modèle inconnu : {model_name!r} (disponibles : {sorted(MODEL_REGISTRY)})"
        )
    merged = {**DEFAULT_PARAMS[model_name], **(params or {})}
    estimator = MODEL_REGISTRY[model_name](**merged)
    return Pipeline([("preprocess", preprocessor), ("model", estimator)])


def train_model(pipeline: Pipeline, X_train: pd.DataFrame, y_train: pd.Series) -> Pipeline:
    """Entraîne le pipeline et le retourne."""
    pipeline.fit(X_train, y_train)
    return pipeline
