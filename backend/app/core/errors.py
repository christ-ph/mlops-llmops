"""Handlers d'erreurs centralisés."""
from flask import Flask, jsonify
from werkzeug.exceptions import HTTPException

from app.core.responses import failure


def register_error_handlers(app: Flask) -> None:
    """Enregistre les handlers qui renvoient l'enveloppe JSON normalisée."""

    @app.errorhandler(HTTPException)
    def handle_http_exception(exc: HTTPException):
        extra = getattr(exc, "data", None) or {}
        details = extra.get("errors") or extra.get("messages")
        message = extra.get("message") or exc.description or exc.name
        payload = failure(exc.code or 500, exc.name, message, details)
        return jsonify(payload), exc.code or 500

    @app.errorhandler(Exception)
    def handle_unexpected_exception(exc: Exception):
        app.logger.exception("Erreur non gérée : %s", exc)
        payload = failure(500, "Internal Server Error", "Erreur interne du serveur")
        return jsonify(payload), 500
