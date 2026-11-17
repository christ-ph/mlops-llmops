"""Pipeline d'entraînement : CSV -> preprocessing -> entraînement -> MLflow -> registry."""
from __future__ import annotations

from pathlib import Path
from typing import Any

import mlflow
from mlflow.models import infer_signature

from mlops.config import (
    ARTIFACT_ROOT,
    PRIMARY_METRIC,
    RANDOM_SEED,
    RAW_DATASET_PATH,
    REGISTERED_MODEL_NAME,
    TARGET_COLUMN,
    TEST_SIZE,
    TRACKING_URI,
)
from mlops.data.ingestion import file_md5, load_csv
from mlops.data.preprocessing import build_preprocessor, split_data
from mlops.evaluation.metrics import compute_classification_metrics
from mlops.registry.registry import configure_mlflow, promote_if_better, register_model
from mlops.training.train import MODEL_REGISTRY, build_pipeline, train_model


def run_training_pipeline(
    model_name: str = "random_forest",
    params: dict[str, Any] | None = None,
    dataset_path: Path | str = RAW_DATASET_PATH,
    target: str = TARGET_COLUMN,
    tracking_uri: str = TRACKING_URI,
    artifact_root: Path | str = ARTIFACT_ROOT,
    registered_model_name: str = REGISTERED_MODEL_NAME,
    test_size: float = TEST_SIZE,
    seed: int = RANDOM_SEED,
) -> dict[str, Any]:
    """Entraîne un modèle, le suit dans MLflow, l'enregistre et le promeut si meilleur."""
    configure_mlflow(tracking_uri=tracking_uri, artifact_root=artifact_root)

    df = load_csv(dataset_path, target)
    split = split_data(df, target, test_size=test_size, seed=seed)
    pipeline = build_pipeline(model_name, build_preprocessor(split.X_train), params)

    with mlflow.start_run(run_name=model_name) as run:
        mlflow.set_tags({"model_name": model_name, "pipeline": "training"})
        mlflow.log_params(
            {
                "model_name": model_name,
                "dataset_path": str(dataset_path),
                "dataset_md5": file_md5(dataset_path),
                "test_size": test_size,
                "seed": seed,
                "n_features": split.X_train.shape[1],
                "n_train_rows": len(split.X_train),
            }
        )

        train_model(pipeline, split.X_train, split.y_train)
        mlflow.log_params(
            {f"model__{k}": v for k, v in pipeline.named_steps["model"].get_params().items()}
        )

        metrics = compute_classification_metrics(pipeline, split.X_test, split.y_test)
        mlflow.log_metrics(metrics)

        signature = infer_signature(split.X_train, pipeline.predict(split.X_train))
        # MLflow 3.x :
        #  - `name=` remplace `artifact_path=` (déprécié)
        #  - `skops_trusted_types` : numpy.dtype (modèles linéaires)
        #    + sklearn.tree._tree.Tree (forêts / boosting)
        model_info = mlflow.sklearn.log_model(
            pipeline,
            name="model",
            signature=signature,
            input_example=split.X_train.head(3),
            skops_trusted_types=["numpy.dtype", "sklearn.tree._tree.Tree"],
        )
        model_uri = model_info.model_uri
        run_id = run.info.run_id

    version = register_model(model_uri, registered_model_name)
    promoted = promote_if_better(registered_model_name, version)

    return {
        "model_name": model_name,
        "run_id": run_id,
        "registered_model": registered_model_name,
        "version": version,
        "promoted": promoted,
        "metrics": metrics,
    }


def compare_models(
    model_names: list[str] | None = None, **kwargs: Any
) -> list[dict[str, Any]]:
    """Entraîne plusieurs modèles et les classe par métrique principale (décroissant)."""
    names = model_names or list(MODEL_REGISTRY)
    results = [run_training_pipeline(model_name=name, **kwargs) for name in names]
    return sorted(results, key=lambda r: r["metrics"][PRIMARY_METRIC], reverse=True)
