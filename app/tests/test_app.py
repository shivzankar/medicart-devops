import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from app import app  # noqa: E402


def client():
    app.config["TESTING"] = True
    return app.test_client()


def test_home():
    r = client().get("/")
    assert r.status_code == 200 and b"MediCart" in r.data


def test_health():
    assert client().get("/health").get_json()["status"] == "UP"


def test_cart_and_checkout():
    c = client()
    c.post("/cart/add/1")
    assert b"Paracetamol" in c.get("/cart").data
    r = c.post("/checkout", data={"name": "Test"})
    assert b"placed" in r.data
    assert client().get("/metrics").get_json()["orders"] >= 1


def test_404_counts_error():
    c = client()
    assert c.get("/nope").status_code == 404
    assert c.get("/metrics").get_json()["errors"] >= 1
