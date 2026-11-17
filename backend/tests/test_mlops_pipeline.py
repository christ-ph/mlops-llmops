"""Tests de la couche MLOps (données, entraînement, MLflow, registry)."""
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

import pandas as pd
import pytest

from mlops.data.ingestion import load_csv, validate_dataframe
from mlops.data.preprocessing import build_preprocessor, split_data
from mlops.datasets.loader import export_breast_cancer_csv
from mlops.pipelines.training_pipeline import run_training_pipeline
from mlops.registry.registry import load_champion_model
from mlops.training.train import build_pipeline


@pytest.fixture(scope="module")
def dataset_path(tmp_path_factory) -> Path:
    return export_breast_cancer_csv(tmp_path_factory.mktemp("data") / "bc.csv")


def test_load_csv(dataset_path):
    df = load_csv(dataset_path, "target")
    assert "target" in df.columns
    assert len(df) > 100


def test_load_csv_missing_file(tmp_path):
    with pytest.raises(FileNotFoundError):
        load_csv(tmp_path / "absent.csv", "target")


def test_validate_missing_target():
    with pytest.raises(ValueError):
        validate_dataframe(pd.DataFrame({"a": [1, 2]}), "target")


def test_split_is_stratified(dataset_path):
    df = load_csv(dataset_path, "target")
    split = split_data(df, "target", test_size=0.2, seed=1)
    assert len(split.X_train) + len(split.X_test) == len(df)
    assert abs(split.y_train.mean() - split.y_test.mean()) < 0.05


def test_preprocessor_handles_categorical_and_missing():
    df = pd.DataFrame({"n": [1.0, None, 3.0], "c": ["a", None, "b"]})
    out = build_preprocessor(df).fit_transform(df)
    assert out.shape[0] == 3


def test_unknown_model_rejected(dataset_path):
    df = load_csv(dataset_path, "target")
    with pytest.raises(ValueError):
        build_pipeline("inconnu", build_preprocessor(df.drop(columns=["target"])))


def test_pipeline_end_to_end(tmp_path, dataset_path):
    result = run_training_pipeline(
        model_name="logistic_regression",
        dataset_path=dataset_path,
        tracking_uri=f"sqlite:///{tmp_path / 'mlflow.db'}",
        artifact_root=tmp_path / "artifacts",
    )
    assert result["metrics"]["test_f1"] > 0.9
    assert result["version"] == "1"
    assert result["promoted"] is True

    model = load_champion_model(result["registered_model"])
    features = load_csv(dataset_path, "target").drop(columns=["target"]).head(5)
    assert len(model.predict(features)) == 5
