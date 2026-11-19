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
