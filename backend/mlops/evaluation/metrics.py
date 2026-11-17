"""Métriques de classification."""
from __future__ import annotations

import pandas as pd
from sklearn.metrics import (
    accuracy_score,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
)


def compute_classification_metrics(
    model, X: pd.DataFrame, y: pd.Series, prefix: str = "test"
) -> dict[str, float]:
    """Accuracy, precision, recall, F1 et ROC-AUC, préfixées (ex. `test_f1`)."""
    y_pred = model.predict(X)
    binary = y.nunique() == 2
    average = "binary" if binary else "weighted"

    metrics: dict[str, float] = {
        "accuracy": accuracy_score(y, y_pred),
        "precision": precision_score(y, y_pred, average=average, zero_division=0),
        "recall": recall_score(y, y_pred, average=average, zero_division=0),
        "f1": f1_score(y, y_pred, average=average, zero_division=0),
    }
    if hasattr(model, "predict_proba"):
        proba = model.predict_proba(X)
        if binary:
            metrics["roc_auc"] = roc_auc_score(y, proba[:, 1])
        else:
            metrics["roc_auc"] = roc_auc_score(
                y, proba, multi_class="ovr", average="weighted"
            )
    return {f"{prefix}_{name}": float(value) for name, value in metrics.items()}
