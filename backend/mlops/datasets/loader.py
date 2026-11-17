"""Accès aux datasets : jeu de démonstration exporté en CSV."""
from __future__ import annotations

from pathlib import Path

from mlops.config import RAW_DATASET_PATH


def export_breast_cancer_csv(
    path: Path | str = RAW_DATASET_PATH, overwrite: bool = False
) -> Path:
    """Exporte le dataset breast cancer (scikit-learn) en CSV, colonne `target` incluse."""
    from sklearn.datasets import load_breast_cancer

    path = Path(path)
    if path.exists() and not overwrite:
        return path
    path.parent.mkdir(parents=True, exist_ok=True)
    frame = load_breast_cancer(as_frame=True).frame
    frame.to_csv(path, index=False)
    return path
