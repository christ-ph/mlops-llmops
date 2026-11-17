"""Enveloppe JSON normalisée des réponses."""
from typing import Any


def success(data: Any) -> dict[str, Any]:
    """Réponse de succès : {"data": ..., "error": None}."""
    return {"data": data, "error": None}


def failure(code: int, name: str, message: str, details: Any = None) -> dict[str, Any]:
    """Réponse d'erreur : {"data": None, "error": {...}}."""
    error: dict[str, Any] = {"code": code, "name": name, "message": message}
    if details:
        error["details"] = details
    return {"data": None, "error": error}
