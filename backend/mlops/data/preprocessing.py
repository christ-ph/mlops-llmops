"""Préparation des données : split et préprocesseur scikit-learn."""
from __future__ import annotations

from dataclasses import dataclass

import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.impute import SimpleImputer
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

from mlops.config import RANDOM_SEED, TEST_SIZE


@dataclass(frozen=True)
class SplitData:
    """Jeux d'entraînement et de test."""

    X_train: pd.DataFrame
    X_test: pd.DataFrame
    y_train: pd.Series
    y_test: pd.Series


def build_preprocessor(X: pd.DataFrame) -> ColumnTransformer:
    """Imputation + scaling (numérique), imputation + one-hot (catégoriel)."""
    numeric = X.select_dtypes(include="number").columns.tolist()
    categorical = [col for col in X.columns if col not in numeric]

    transformers = []
    if numeric:
        transformers.append(
            (
                "num",
                Pipeline(
                    [
                        ("imputer", SimpleImputer(strategy="median")),
                        ("scaler", StandardScaler()),
                    ]
                ),
                numeric,
            )
        )
    if categorical:
        transformers.append(
            (
                "cat",
                Pipeline(
                    [
                        ("imputer", SimpleImputer(strategy="most_frequent")),
                        ("encoder", OneHotEncoder(handle_unknown="ignore")),
                    ]
                ),
                categorical,
            )
        )
    return ColumnTransformer(transformers)


def split_data(
    df: pd.DataFrame,
    target: str,
    test_size: float = TEST_SIZE,
    seed: int = RANDOM_SEED,
) -> SplitData:
    """Split train/test stratifié sur la cible."""
    X = df.drop(columns=[target])
    y = df[target]
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=test_size, random_state=seed, stratify=y
    )
    return SplitData(X_train, X_test, y_train, y_test)
