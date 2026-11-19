#!/usr/bin/env bash
# setup_monitoring.sh
# Ajoute Prometheus + Grafana à la stack Docker Compose.
# Idempotent : ne remplace pas les fichiers existants sans --force.
#
# Usage : ./setup_monitoring.sh [--force]
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

write_file() {
  local path="$1"; local existed=0; [ -e "$path" ] && existed=1
  if [ "$existed" -eq 1 ] && [ "$FORCE" -ne 1 ]; then
    echo "⏭  existe déjà : ${path#"$ROOT_DIR"/}"; cat >/dev/null; return
  fi
  if [ "$existed" -eq 1 ]; then cp "$path" "$path.bak"; echo "✔  backup      : ${path#"$ROOT_DIR"/}.bak"; fi
  mkdir -p "$(dirname "$path")"; cat >"$path"
  [ "$existed" -eq 1 ] && echo "✔  mis à jour  : ${path#"$ROOT_DIR"/}" || echo "✔  créé        : ${path#"$ROOT_DIR"/}"
}

# ------------------------------------------------------------ monitoring module
write_file "$BACKEND_DIR/app/monitoring.py" <<'PYEOF'
"""Métriques Prometheus pour l'API MLOps."""
from prometheus_client import Counter, Gauge, Histogram

# Prédictions : compteur par modèle et version
PREDICTION_COUNTER = Counter(
    "mlops_predictions_total",
    "Nombre total de prédictions",
    ["model_name", "model_version"],
)

# Latence des prédictions (secondes)
PREDICTION_LATENCY = Histogram(
    "mlops_prediction_latency_seconds",
    "Latence des prédictions (secondes)",
    ["model_name"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0),
)

# Distribution des classes prédites (0 = malin, 1 = bénin)
PREDICTION_DISTRIBUTION = Counter(
    "mlops_prediction_class_total",
    "Distribution des classes prédites",
    ["model_name", "predicted_class"],
)

# Taille des lots de prédiction (nombre de records par requête)
PREDICTION_BATCH_SIZE = Histogram(
    "mlops_prediction_batch_size",
    "Nombre de records par requête de prédiction",
    buckets=(1, 2, 5, 10, 20, 50, 100),
)

# État du modèle (1 = chargé, 0 = non chargé)
MODEL_LOADED = Gauge(
    "mlops_model_loaded",
    "1 si le modèle champion est en cache, 0 sinon",
)
PYEOF

# ----------------------------------------- patch predictor.py (instrumentation)
PREDICTOR="$BACKEND_DIR/mlops/registry/predictor.py"
if [ -f "$PREDICTOR" ] && ! grep -q "PREDICTION_LATENCY" "$PREDICTOR"; then
  cp "$PREDICTOR" "$PREDICTOR.bak"
  python3 - "$PREDICTOR" <<'PYEOF'
import sys
from pathlib import Path
p = Path(sys.argv[1]); src = p.read_text(encoding="utf-8")

# Ajouter imports
if "from app.monitoring import" not in src:
    src = src.replace(
        "import pandas as pd",
        "import time\n\nimport pandas as pd\n\nfrom app.monitoring import (\n    MODEL_LOADED,\n    PREDICTION_BATCH_SIZE,\n    PREDICTION_COUNTER,\n    PREDICTION_DISTRIBUTION,\n    PREDICTION_LATENCY,\n)",
        1,
    )

# Instrumenter predict_records
old_fn = '''def predict_records(records: list[dict[str, Any]]) -> dict[str, Any]:
    """Prédit sur une liste de dicts (features brutes)."""
    model = get_champion()
    df = pd.DataFrame(records)
    predictions = model.predict(df)

    result: dict[str, Any] = {"predictions": [int(p) for p in predictions]}

    raw = _extract_raw_model(model)
    if hasattr(raw, "predict_proba"):
        proba = raw.predict_proba(df)
        result["probabilities"] = proba.tolist()

    return result'''

new_fn = '''def predict_records(records: list[dict[str, Any]]) -> dict[str, Any]:
    """Prédit sur une liste de dicts (features brutes)."""
    model_name = REGISTERED_MODEL_NAME
    model = get_champion()
    MODEL_LOADED.set(1)

    df = pd.DataFrame(records)
    PREDICTION_BATCH_SIZE.observe(len(df))

    start = time.perf_counter()
    predictions = model.predict(df)
    elapsed = time.perf_counter() - start
    PREDICTION_LATENCY.labels(model_name=model_name).observe(elapsed)

    pred_list = [int(p) for p in predictions]
    for p in pred_list:
        PREDICTION_COUNTER.labels(model_name=model_name, model_version="champion").inc()
        PREDICTION_DISTRIBUTION.labels(model_name=model_name, predicted_class=str(p)).inc()

    result: dict[str, Any] = {"predictions": pred_list}

    raw = _extract_raw_model(model)
    if hasattr(raw, "predict_proba"):
        proba = raw.predict_proba(df)
        result["probabilities"] = proba.tolist()

    return result'''

if old_fn not in src:
    print("⚠  Fonction predict_records non trouvée — patch manuel nécessaire", file=sys.stderr); sys.exit(1)

src = src.replace(old_fn, new_fn, 1)
p.write_text(src, encoding="utf-8")
print("✔  patché      : predictor.py (instrumentation Prometheus)")
PYEOF
fi

# ------------------------------------- patch app/__init__.py (metrics init)
INIT="$BACKEND_DIR/app/__init__.py"
if [ -f "$INIT" ] && ! grep -q "GunicornPrometheusMetrics" "$INIT"; then
  cp "$INIT" "$INIT.bak"
  python3 - "$INIT" <<'PYEOF'
import sys
from pathlib import Path
p = Path(sys.argv[1]); src = p.read_text(encoding="utf-8")

# Import
if "GunicornPrometheusMetrics" not in src:
    src = src.replace(
        "from app.api import register_api",
        "from prometheus_flask_exporter.multiprocess import GunicornPrometheusMetrics\n\nfrom app.api import register_api",
        1,
    )

# Initialisation après extensions
if "metrics = GunicornPrometheusMetrics" not in src:
    src = src.replace(
        "api.init_app(app)",
        "metrics = GunicornPrometheusMetrics(app)  # noqa: F841\n    api.init_app(app)",
        1,
    )

p.write_text(src, encoding="utf-8")
print("✔  patché      : app/__init__.py (GunicornPrometheusMetrics)")
PYEOF
fi

# -------------------------------------------------------- prometheus.yml
write_file "$ROOT_DIR/infrastructure/monitoring/prometheus.yml" <<'YAMLEOF'
global:
  scrape_interval: 10s
  evaluation_interval: 10s

scrape_configs:
  - job_name: "mlops-api"
    static_configs:
      - targets: ["api:8000"]
YAMLEOF

# ------------------------------------------------ grafana datasource
write_file "$ROOT_DIR/infrastructure/monitoring/grafana-datasource.yml" <<'YAMLEOF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
YAMLEOF

# ---------------------------------------------- grafana dashboard (MLOps)
write_file "$ROOT_DIR/infrastructure/monitoring/grafana-dashboard.yml" <<'YAMLEOF'
apiVersion: 1
providers:
  - name: "MLOps"
    orgId: 1
    folder: "MLOps"
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    options:
      path: /etc/grafana/provisioning/dashboards
YAMLEOF

write_file "$ROOT_DIR/infrastructure/monitoring/dashboard-mlops.json" <<'JSONEOF'
{
  "title": "MLOps API Monitoring",
  "uid": "mlops-api",
  "panels": [
    {
      "title": "Prédictions / seconde",
      "type": "timeseries",
      "targets": [{"expr": "rate(mlops_predictions_total[1m])"}]
    },
    {
      "title": "Latence P95 (s)",
      "type": "timeseries",
      "targets": [{"expr": "histogram_quantile(0.95, rate(mlops_prediction_latency_seconds_bucket[5m]))"}]
    },
    {
      "title": "Distribution des classes",
      "type": "piechart",
      "targets": [{"expr": "sum by (predicted_class) (mlops_prediction_class_total)"}]
    },
    {
      "title": "Taille des lots",
      "type": "timeseries",
      "targets": [{"expr": "rate(mlops_prediction_batch_size_sum[1m]) / rate(mlops_prediction_batch_size_count[1m])"}]
    }
  ],
  "schemaVersion": 39,
  "version": 1
}
JSONEOF

# ------------------------------------------ patch docker-compose.yml
COMPOSE="$ROOT_DIR/docker-compose.yml"
if ! grep -q "prometheus:" "$COMPOSE"; then
  cp "$COMPOSE" "$COMPOSE.bak"
  python3 - "$COMPOSE" <<'PYEOF'
import sys
from pathlib import Path
p = Path(sys.argv[1]); src = p.read_text(encoding="utf-8")

addition = '''
  prometheus:
    image: prom/prometheus:v2.55.0
    volumes:
      - ./infrastructure/monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    ports:
      - "9090:9090"
    depends_on:
      - api
    restart: unless-stopped

  grafana:
    image: grafana/grafana:11.3.0
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: admin
    volumes:
      - grafana_data:/var/lib/grafana
      - ./infrastructure/monitoring/grafana-datasource.yml:/etc/grafana/provisioning/datasources/datasource.yml:ro
      - ./infrastructure/monitoring/grafana-dashboard.yml:/etc/grafana/provisioning/dashboards/dashboard.yml:ro
      - ./infrastructure/monitoring/dashboard-mlops.json:/etc/grafana/provisioning/dashboards/dashboard-mlops.json:ro
    ports:
      - "3000:3000"
    depends_on:
      - prometheus
    restart: unless-stopped
'''

if "volumes:" in src:
    src = src.replace("\nvolumes:\n", addition + "\nvolumes:\n  prometheus_data:\n  grafana_data:\n", 1)
else:
    src += "\nvolumes:\n  prometheus_data:\n  grafana_data:\n"

p.write_text(src, encoding="utf-8")
print("✔  patché      : docker-compose.yml (prometheus + grafana)")
PYEOF
fi

# ------------------------------------------ dépendance Python
cd "$BACKEND_DIR"
if ! grep -q "prometheus-flask-exporter" pyproject.toml 2>/dev/null; then
  echo "==> Ajout de prometheus-flask-exporter..."
  uv add "prometheus-flask-exporter>=0.23"
else
  echo "⏭  prometheus-flask-exporter déjà présent"
fi

echo ""
echo "==============================================================="
echo "Terminé. Commandes :"
echo ""
echo "  docker compose build api"
echo "  docker compose up -d prometheus grafana"
echo "  docker compose logs -f api"
echo ""
echo "  # Vérifier /metrics"
echo "  curl -s http://localhost:8000/metrics | grep mlops_"
echo ""
echo "  # Interfaces"
echo "  Prometheus : http://localhost:9090"
echo "  Grafana    : http://localhost:3000  (admin/admin)"
echo "==============================================================="
