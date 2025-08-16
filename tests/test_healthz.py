import json

def test_healthz(client):
    resp = client.get("/healthz")
    assert resp.status_code == 200
    data = json.loads(resp.content)
    assert data.get("status") == "ok"
