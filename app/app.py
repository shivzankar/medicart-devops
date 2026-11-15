"""MediCart - a small online pharmacy used to demonstrate a DevOps pipeline.

Endpoints
  /                 product catalogue
  /cart             view cart
  /cart/add/<id>    add a product to the cart (POST)
  /checkout         place an order (POST)
  /orders           list placed orders
  /health           health check (used by Docker HEALTHCHECK / monitoring)
  /metrics          simple JSON metrics
  /api/products     JSON product list
"""
import logging
import os
import socket
import time
import uuid
from logging.handlers import RotatingFileHandler

from flask import Flask, jsonify, redirect, render_template, request, session, url_for

APP_VERSION = os.getenv("APP_VERSION", "1.0.0")
LOG_DIR = os.getenv("LOG_DIR", "/tmp/medicart-logs")

app = Flask(__name__)
app.secret_key = os.getenv("SECRET_KEY", "dev-only-change-me")

# ---------- logging (shipped to CloudWatch by the agent) ----------
os.makedirs(LOG_DIR, exist_ok=True)
_handler = RotatingFileHandler(os.path.join(LOG_DIR, "app.log"), maxBytes=1_000_000, backupCount=3)
_handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
log = logging.getLogger("medicart")
log.setLevel(logging.INFO)
log.addHandler(_handler)
log.addHandler(logging.StreamHandler())

PRODUCTS = [
    {"id": 1, "name": "Paracetamol 500mg", "category": "Pain Relief", "price": 35.0, "stock": 120},
    {"id": 2, "name": "Vitamin C 1000mg", "category": "Supplements", "price": 220.0, "stock": 60},
    {"id": 3, "name": "Cetirizine 10mg", "category": "Allergy", "price": 48.0, "stock": 80},
    {"id": 4, "name": "ORS Sachets (Pack of 10)", "category": "Hydration", "price": 95.0, "stock": 200},
    {"id": 5, "name": "Digital Thermometer", "category": "Devices", "price": 299.0, "stock": 25},
    {"id": 6, "name": "Hand Sanitizer 500ml", "category": "Hygiene", "price": 150.0, "stock": 90},
]
ORDERS = []
METRICS = {"requests": 0, "orders": 0, "errors": 0, "started_at": time.time()}


def _product(pid):
    return next((p for p in PRODUCTS if p["id"] == pid), None)


def _cart_items():
    items, total = [], 0.0
    for pid, qty in session.get("cart", {}).items():
        p = _product(int(pid))
        if p:
            items.append({**p, "qty": qty, "subtotal": p["price"] * qty})
            total += p["price"] * qty
    return items, total


@app.before_request
def _count():
    METRICS["requests"] += 1


@app.after_request
def _access_log(resp):
    log.info("%s %s %s", request.method, request.path, resp.status_code)
    return resp


@app.errorhandler(404)
def _not_found(_e):
    METRICS["errors"] += 1
    log.error("404 Not Found: %s", request.path)
    return render_template("error.html", message="Page not found"), 404


@app.context_processor
def _globals():
    return {"version": APP_VERSION, "host": socket.gethostname(),
            "cart_count": sum(session.get("cart", {}).values())}


@app.route("/")
def index():
    return render_template("index.html", products=PRODUCTS)


@app.route("/cart")
def cart():
    items, total = _cart_items()
    return render_template("cart.html", items=items, total=total)


@app.route("/cart/add/<int:pid>", methods=["POST"])
def add_to_cart(pid):
    if not _product(pid):
        METRICS["errors"] += 1
        log.error("Add to cart failed, unknown product %s", pid)
        return render_template("error.html", message="Product not found"), 404
    cart_ = session.get("cart", {})
    cart_[str(pid)] = cart_.get(str(pid), 0) + 1
    session["cart"] = cart_
    return redirect(url_for("index"))


@app.route("/checkout", methods=["POST"])
def checkout():
    items, total = _cart_items()
    if not items:
        return redirect(url_for("cart"))
    order = {"id": uuid.uuid4().hex[:8].upper(), "items": items, "total": total,
             "customer": request.form.get("name", "Guest")[:50], "time": time.strftime("%Y-%m-%d %H:%M:%S")}
    ORDERS.append(order)
    METRICS["orders"] += 1
    session["cart"] = {}
    log.info("ORDER_PLACED id=%s total=%.2f", order["id"], total)
    return render_template("order.html", order=order)


@app.route("/orders")
def orders():
    return render_template("orders.html", orders=ORDERS)


@app.route("/health")
def health():
    return jsonify(status="UP", version=APP_VERSION, host=socket.gethostname())


@app.route("/metrics")
def metrics():
    return jsonify(**METRICS, uptime_seconds=int(time.time() - METRICS["started_at"]),
                   products=len(PRODUCTS), version=APP_VERSION)


@app.route("/api/products")
def api_products():
    return jsonify(PRODUCTS)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "5000")))
