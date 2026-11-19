#!/usr/bin/env bash
# setup_docker.sh
# Crée l'infrastructure Docker Compose : API + MLflow + PostgreSQL.
#
# Idempotent : les fichiers existants ne sont pas écrasés sans --force.
# Avec --force : backup .bak avant écrasement.
#
# Usage :
#   bash setup_docker.sh
#   bash setup_docker.sh --force
set -euo pipefail

FORCE=0
for arg in "$@"; do
  case "$arg" in
    -f|--force) FORCE=1 ;;
    *) echo "Argument inconnu : $arg" >&2; exit 1 ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
DOCKER_DIR="$ROOT_DIR/infrastructure/docker"

if [ ! -d "$BACKEND_DIR/app" ] || [ ! -d "$BACKEND_DIR/mlops" ]; then
  echo "✖ Ce script doit être lancé depuis la racine du projet (là où se trouve backend/)." >&2
  exit 1
fi

write_file() {
  local path="$1"
  local existed=0
  [ -e "$path" ] && existed=1

  if [ "$existed" -eq 1 ] && [ "$FORCE" -ne 1 ]; then
    echo "⏭  existe déjà : ${path#"$ROOT_DIR"/}"
    cat >/dev/null
    return
  fi

  if [ "$existed" -eq 1 ]; then
    cp "$path" "$path.bak"
    echo "✔  backup      : ${path#"$ROOT_DIR"/}.bak"
  fi

  mkdir -p "$(dirname "$path")"
  cat >"$path"
  if [ "$existed" -eq 1 ]; then
    echo "✔  mis à jour  : ${path#"$ROOT_DIR"/}"
  else
    echo "✔  créé        : ${path#"$ROOT_DIR"/}"
  fi
}

# -------------------------------------------------------- WSGI entrypoint
write_file "$BACKEND_DIR/wsgi.py" <<'PYEOF'
"""Entrypoint WSGI pour gunicorn (utilisé en Docker)."""
import os

from app import create_app

app = create_app(os.environ.get("APP_ENV", "production"))
PYEOF

# ------------------------------------------------------- .dockerignore
write_file "$BACKEND_DIR/.dockerignore" <<'DOCKERIGNORE'
.venv/
__pycache__/
*.pyc
*.pyo
.pytest_cache/
.ruff_cache/
.coverage
htmlcov/
*.bak
.env
.git/
.gitignore
DOCKERIGNORE

# ----------------------------------------------------------- Dockerfile
write_file "$DOCKER_DIR/Dockerfile.api" <<'DOCKEREOF'
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

WORKDIR /app/backend

# Installer les dépendances d'abord (cache Docker)
COPY backend/pyproject.toml backend/uv.lock ./
RUN uv sync --frozen --no-dev

# Copier le code applicatif
COPY backend/ /app/backend/
COPY infrastructure/docker/entrypoint-api.sh /app/infrastructure/docker/entrypoint-api.sh

RUN mkdir -p /app/datasets/raw /app/datasets/processed /app/datasets/external \
    && mkdir -p /app/experiments/artifacts \
    && chmod +x /app/infrastructure/docker/entrypoint-api.sh

ENV PATH="/app/backend/.venv/bin:$PATH"

EXPOSE 8000

CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--timeout", "120", "wsgi:app"]
DOCKEREOF

# ---------------------------------------------------- entrypoint API
write_file "$DOCKER_DIR/entrypoint-api.sh" <<'ENTRYEOF'
#!/usr/bin/env bash
# Entrypoint du conteneur API.
# 1. attend PostgreSQL
# 2. attend MLflow
# 3. crée les tables SQLAlchemy
# 4. vérifie l'existence du champion — sinon entraînement initial
# 5. démarre gunicorn
set -euo pipefail

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

echo "==> Création des tables (SQLAlchemy)..."
python - <<'PYEOF'
from app import create_app
from app.extensions import db
app = create_app("production")
with app.app_context():
    db.create_all()
print("Tables créées ou déjà présentes")
PYEOF

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

echo "==> Démarrage de gunicorn..."
exec "$@"
ENTRYEOF

# ---------------------------------------------------- init PostgreSQL
write_file "$DOCKER_DIR/init-postgres.sql" <<'SQLEOF'
-- Crée la base MLflow en plus de la base modelops (créée automatiquement).
CREATE DATABASE mlflow OWNER modelops;
SQLEOF

# ----------------------------------------------------- docker-compose
write_file "$ROOT_DIR/docker-compose.yml" <<'COMPOSEEOF'
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: modelops
      POSTGRES_PASSWORD: modelops
      POSTGRES_DB: modelops
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./infrastructure/docker/init-postgres.sql:/docker-entrypoint-initdb.d/init.sql:ro
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U modelops -d modelops"]
      interval: 5s
      timeout: 5s
      retries: 10
    restart: unless-stopped

  mlflow:
    build:
      context: .
      dockerfile: infrastructure/docker/Dockerfile.api
    command:
      - mlflow
      - server
      - --backend-store-uri
      - postgresql+psycopg://modelops:modelops@postgres:5432/mlflow
      - --artifacts-destination
      - /mlflow/artifacts
      - --host
      - 0.0.0.0
      - --port
      - "5000"
    volumes:
      - mlflow_artifacts:/mlflow/artifacts
    depends_on:
      postgres:
        condition: service_healthy
    ports:
      - "5000:5000"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/health"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s
    restart: unless-stopped

  api:
    build:
      context: .
      dockerfile: infrastructure/docker/Dockerfile.api
    entrypoint: ["/app/infrastructure/docker/entrypoint-api.sh"]
    command:
      - gunicorn
      - --bind
      - 0.0.0.0:8000
      - --workers
      - "2"
      - --timeout
      - "120"
      - wsgi:app
    environment:
      APP_ENV: production
      FLASK_APP: app
      DATABASE_URL: postgresql+psycopg://modelops:modelops@postgres:5432/modelops
      MLFLOW_TRACKING_URI: http://mlflow:5000
      SECRET_KEY: ${SECRET_KEY:-change-me-in-production}
      JWT_SECRET_KEY: ${JWT_SECRET_KEY:-change-me-in-production}
      CORS_ORIGINS: ${CORS_ORIGINS:-http://localhost:5173,http://localhost:3000}
    depends_on:
      postgres:
        condition: service_healthy
      mlflow:
        condition: service_healthy
    ports:
      - "8000:8000"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/api/v1/health"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 90s
    restart: unless-stopped

volumes:
  postgres_data:
  mlflow_artifacts:
COMPOSEEOF

# ------------------------------------ Patch mlops/config.py (tracking URI)
CONFIG_FILE="$BACKEND_DIR/mlops/config.py"
if [ -f "$CONFIG_FILE" ]; then
  cp "$CONFIG_FILE" "$CONFIG_FILE.bak"
  echo "✔  backup      : backend/mlops/config.py.bak"
  python3 - "$CONFIG_FILE" <<'PYEOF'
import re, sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text(encoding="utf-8")

if "MLFLOW_TRACKING_URI" in src:
    print("⏭  mlops/config.py lit déjà MLFLOW_TRACKING_URI")
    sys.exit(0)

old = 'TRACKING_URI = f"sqlite:///{EXPERIMENTS_DIR / \'mlflow.db\'}"'
new = (
    'TRACKING_URI = os.environ.get(\n'
    '    "MLFLOW_TRACKING_URI",\n'
    '    f"sqlite:///{EXPERIMENTS_DIR / \'mlflow.db\'}",\n'
    ')'
)
if old not in src:
    print(f"⚠  ligne TRACKING_URI non trouvée dans {path} — patch manuel nécessaire", file=sys.stderr)
    print(f"   Cherche : {old}", file=sys.stderr)
    sys.exit(1)

if "import os" not in src.split("\n\n")[0]:
    src = src.replace("from __future__ import annotations\n", "from __future__ import annotations\n\nimport os\n", 1)

src = src.replace(old, new, 1)
path.write_text(src, encoding="utf-8")
print("✔  patché      : backend/mlops/config.py (MLFLOW_TRACKING_URI depuis env)")
PYEOF
fi

# -------------------- Patch registry.py (artifact_location seulement en local)
REGISTRY_FILE="$BACKEND_DIR/mlops/registry/registry.py"
if [ -f "$REGISTRY_FILE" ]; then
  cp "$REGISTRY_FILE" "$REGISTRY_FILE.bak"
  echo "✔  backup      : backend/mlops/registry/registry.py.bak"
  python3 - "$REGISTRY_FILE" <<'PYEOF'
import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text(encoding="utf-8")

if "is_local_tracking" in src:
    print("⏭  registry.py gère déjà is_local_tracking")
    sys.exit(0)

old = '''    prefix = "sqlite:///"
    if tracking_uri.startswith(prefix):
        Path(tracking_uri[len(prefix):]).parent.mkdir(parents=True, exist_ok=True)
    artifact_root = Path(artifact_root).resolve()
    artifact_root.mkdir(parents=True, exist_ok=True)

    mlflow.set_tracking_uri(tracking_uri)
    client = MlflowClient()
    experiment = client.get_experiment_by_name(experiment_name)
    if experiment is None:
        experiment_id = client.create_experiment(
            experiment_name, artifact_location=artifact_root.as_uri()
        )
    else:
        experiment_id = experiment.experiment_id
    mlflow.set_experiment(experiment_id=experiment_id)
    return experiment_id'''

new = '''    prefix = "sqlite:///"
    is_local_tracking = tracking_uri.startswith(prefix)

    if is_local_tracking:
        Path(tracking_uri[len(prefix):]).parent.mkdir(parents=True, exist_ok=True)
        artifact_root = Path(artifact_root).resolve()
        artifact_root.mkdir(parents=True, exist_ok=True)

    mlflow.set_tracking_uri(tracking_uri)
    client = MlflowClient()
    experiment = client.get_experiment_by_name(experiment_name)
    if experiment is None:
        if is_local_tracking:
            experiment_id = client.create_experiment(
                experiment_name, artifact_location=artifact_root.as_uri()
            )
        else:
            experiment_id = client.create_experiment(experiment_name)
    else:
        experiment_id = experiment.experiment_id
    mlflow.set_experiment(experiment_id=experiment_id)
    return experiment_id'''

if old not in src:
    print(f"⚠  bloc configure_mlflow non trouvé — patch manuel nécessaire dans {path}", file=sys.stderr)
    print("   Vérifie que la fonction configure_mlflow est inchangée.", file=sys.stderr)
    sys.exit(1)

src = src.replace(old, new, 1)
path.write_text(src, encoding="utf-8")
print("✔  patché      : backend/mlops/registry/registry.py (is_local_tracking)")
PYEOF
fi

# ------------------------------------------ Dépendances Python
cd "$BACKEND_DIR"
if ! grep -q '"psycopg\[binary\]' pyproject.toml 2>/dev/null; then
  echo "==> Ajout de psycopg[binary] et gunicorn..."
  uv add "psycopg[binary]" gunicorn
else
  echo "⏭  pyproject.toml contient déjà psycopg[binary]"
fi

# ------------------------------------------------------ .gitignore
cd "$ROOT_DIR"
if [ -f .gitignore ]; then
  for entry in "docker-compose.override.yml" ".env.docker" "pgdata/"; do
    grep -q "^$entry$" .gitignore || echo "$entry" >> .gitignore
  done
fi

cat <<'EOF'

===============================================================
Terminé.

Commandes à exécuter ensuite :

  # 1. Construire les images (première fois, ~3-5 min)
  docker compose build

  # 2. Démarrer l'infrastructure
  docker compose up -d

  # 3. Suivre les logs (l'API attend Postgres, MLflow, puis entraîne
  #    les 3 modèles — compter ~60-90 s au premier démarrage)
  docker compose logs -f api

  # 4. Vérifier que tout est vert
  docker compose ps

  # 5. Tester l'API
  curl -s http://localhost:8000/api/v1/predict/metadata | python -m json.tool
  curl -s -X POST http://localhost:8000/api/v1/predict \
    -H "Content-Type: application/json" \
    -d '{"records": [{"mean radius": 17.99, "mean texture": 10.38}]}' \
    | python -m json.tool

  # 6. UI MLflow
  xdg-open http://localhost:5000

  # 7. Arrêter
  docker compose down

  # 8. Tout réinitialiser (supprime DB + artifacts)
  docker compose down -v

Swagger : http://localhost:8000/api/docs
===============================================================
EOF
