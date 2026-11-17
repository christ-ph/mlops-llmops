"""Chargement et validation d'un dataset CSV."""
from __future__ import annotations

import hashlib
from pathlib import Path

import pandas as pd


def validate_dataframe(df: pd.DataFrame, target: str) -> None:
    """Lève ValueError si le dataset est inutilisable pour une classification."""
    if df.empty:
        raise ValueError("Le dataset est vide")
    if target not in df.columns:
        raise ValueError(f"Colonne cible absente : {target!r}")
    if df[target].isna().any():
        raise ValueError("La colonne cible contient des valeurs manquantes")
    if df[target].nunique() < 2:
        raise ValueError("La colonne cible doit avoir au moins 2 classes")


def load_csv(path: Path | str, target: str) -> pd.DataFrame:
    """Charge un CSV et le valide."""
    path = Path(path)
    if not path.is_file():
        raise FileNotFoundError(f"Dataset introuvable : {path}")
    df = pd.read_csv(path)
    validate_dataframe(df, target)
    return df


def file_md5(path: Path | str) -> str:
    """Empreinte du fichier, pour tracer la version du dataset dans MLflow."""
    digest = hashlib.md5()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
