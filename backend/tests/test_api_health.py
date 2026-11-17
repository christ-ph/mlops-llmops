"""Tests de l'API de santé et du format d'erreur."""


def test_health_ok(client):
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    body = response.get_json()
    assert body["error"] is None
    assert body["data"] == {"status": "ok", "database": "up"}


def test_liveness(client):
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.get_json()["data"]["status"] == "ok"


def test_unknown_route_returns_error_envelope(client):
    response = client.get("/api/v1/inexistant")
    assert response.status_code == 404
    body = response.get_json()
    assert body["data"] is None
    assert body["error"]["code"] == 404
