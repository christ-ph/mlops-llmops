"""Configuration centrale de la couche MLOps (aucune dépendance Flask)."""
from __future__ import annotations

from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
PROJECT_ROOT = BACKEND_DIR.parent

# Données
DATASET_DIR = PROJECT_ROOT / "datasets"
RAW_DATASET_PATH = DATASET_DIR / "raw" / "breast_cancer.csv"
TARGET_COLUMN = "target"

# MLflow (backend SQLite local : requis pour le Model Registry)
PROJECT_ROOT = BACKEND_DIR.parent   # = ai-modelops-platform/
EXPERIMENTS_DIR = PROJECT_ROOT / "experiments"
TRACKING_URI = f"sqlite:///{EXPERIMENTS_DIR / 'mlflow.db'}"
ARTIFACT_ROOT = EXPERIMENTS_DIR / "artifacts"
EXPERIMENT_NAME = "breast-cancer-classification"
REGISTERED_MODEL_NAME = "breast-cancer-classifier"
CHAMPION_ALIAS = "champion"
PRIMARY_METRIC = "test_f1"

# Entraînement
RANDOM_SEED = 42
TEST_SIZE = 0.2
