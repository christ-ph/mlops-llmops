"""Liveness probe (utilisée plus tard par Docker/Kubernetes)."""
from flask import Blueprint, jsonify

from app.core.responses import success

bp = Blueprint("liveness", __name__)


@bp.get("/healthz")
def healthz():
    """Le process répond : aucune dépendance externe testée."""
    return jsonify(success({"status": "ok"}))
