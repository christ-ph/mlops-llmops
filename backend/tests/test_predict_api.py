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
