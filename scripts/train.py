#!/usr/bin/env python
"""CLI d'entraînement.

Usage (depuis backend/) :
    uv run python ../scripts/train.py --model all
    uv run python ../scripts/train.py --model random_forest
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1] / "backend"
sys.path.insert(0, str(BACKEND_DIR))

from mlops.config import PRIMARY_METRIC, RAW_DATASET_PATH  # noqa: E402
from mlops.datasets.loader import export_breast_cancer_csv  # noqa: E402
from mlops.pipelines.training_pipeline import (  # noqa: E402
    compare_models,
    run_training_pipeline,
)
from mlops.training.train import MODEL_REGISTRY  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(description="Entraîne et enregistre un modèle.")
    parser.add_argument(
        "--model", default="all", choices=[*MODEL_REGISTRY, "all"], help="Modèle à entraîner"
    )
    args = parser.parse_args()

    export_breast_cancer_csv(RAW_DATASET_PATH)

    results = (
        compare_models()
        if args.model == "all"
        else [run_training_pipeline(model_name=args.model)]
    )
    print(f"\n{'modèle':<22}{PRIMARY_METRIC:>10}  version  champion")
    for r in results:
        print(
            f"{r['model_name']:<22}{r['metrics'][PRIMARY_METRIC]:>10.4f}"
            f"  v{r['version']:<6}  {'oui' if r['promoted'] else 'non'}"
        )


if __name__ == "__main__":
    main()
