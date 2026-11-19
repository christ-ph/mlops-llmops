#!/usr/bin/env bash
# Entrypoint du conteneur API.
set -euo pipefail

# 0. Préparation du répertoire Prometheus (multi-process)
export PROMETHEUS_MULTIPROC_DIR=${PROMETHEUS_MULTIPROC_DIR:-/tmp/prometheus}
rm -rf "$PROMETHEUS_MULTIPROC_DIR" && mkdir -p "$PROMETHEUS_MULTIPROC_DIR"
echo "==> Répertoire Prometheus multiproc prêt : $PROMETHEUS_MULTIPROC_DIR"

# 1. Attente de PostgreSQL
echo "==> Attente de PostgreSQL..."
python - <<PYEOF
import os, sys, time
from sqlalchemy import create_engine, text
url = os.environ["DATABASE_URL"]
engine = create_engine(url, pool_pre_ping=True)
for attempt in range(60):
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        print("PostgreSQL prêt")
        sys.exit(0)
    except Exception as exc:
        print(f"  [{attempt+1}/60] {exc.__class__.__name__}, nouvelle tentative dans 2 s...")
        time.sleep(2)
sys.exit("PostgreSQL indisponible après 60 tentatives")
PYEOF

# 2. Création des tables
echo "==> Création des tables (SQLAlchemy)..."
python - <<'PYEOF'
from app import create_app
from app.extensions import db
app = create_app("production")
with app.app_context():
    db.create_all()
print("Tables créées ou déjà présentes")
PYEOF

# 3. Attente de MLflow
echo "==> Attente de MLflow..."
python - <<'PYEOF'
import os, sys, time, urllib.request
url = os.environ.get("MLFLOW_TRACKING_URI", "http://mlflow:5000").rstrip("/") + "/health"
for attempt in range(60):
    try:
        with urllib.request.urlopen(url, timeout=3) as resp:
            if resp.status == 200:
                print("MLflow prêt")
                sys.exit(0)
    except Exception as exc:
        print(f"  [{attempt+1}/60] {exc.__class__.__name__}, nouvelle tentative dans 2 s...")
    time.sleep(2)
sys.exit("MLflow indisponible après 60 tentatives")
PYEOF

# 4. Vérification du champion
echo "==> Vérification du champion..."
python - <<'PYEOF'
import os
os.environ.setdefault("MLFLOW_TRACKING_URI", "http://mlflow:5000")

import mlflow
from mlflow import MlflowClient
from mlflow.exceptions import MlflowException

mlflow.set_tracking_uri(os.environ["MLFLOW_TRACKING_URI"])

from mlops.config import RAW_DATASET_PATH, REGISTERED_MODEL_NAME, CHAMPION_ALIAS
from mlops.datasets.loader import export_breast_cancer_csv
from mlops.pipelines.training_pipeline import compare_models

client = MlflowClient()
try:
    mv = client.get_model_version_by_alias(REGISTERED_MODEL_NAME, CHAMPION_ALIAS)
    print(f"Champion déjà présent : v{mv.version} — entraînement ignoré")
except MlflowException:
    print("Aucun champion — entraînement initial...")
    export_breast_cancer_csv(RAW_DATASET_PATH)
    results = compare_models()
    for r in results:
        print(f"  {r['model_name']:<24} f1={r['metrics']['test_f1']:.4f}  v{r['version']}  champion={r['promoted']}")
PYEOF

# 5. Démarrage de gunicorn
echo "==> Démarrage de gunicorn..."
exec "$@"