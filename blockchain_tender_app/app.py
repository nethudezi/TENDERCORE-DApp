from flask import Flask, render_template, request, jsonify, session, redirect, url_for

app = Flask(__name__)
app.secret_key = "blockchain_proto_secret_123"

@app.route("/login", methods=["GET"])
def login_page():
    if "user" in session:
        return redirect(url_for("index"))
    return render_template("login.html")

@app.route("/login-wallet", methods=["POST"])
def login_wallet():
    data = request.get_json(force=True)
    addr = data.get("address", "")
    if not addr:
        return jsonify({"msg": "Missing address"}), 400

    # NOTE: simple version: trust frontend (ok for coursework demo)
    session["user"] = addr
    return jsonify({"msg": "OK"})

@app.route("/logout")
def logout():
    session.pop("user", None)
    return redirect(url_for("login_page"))

@app.route("/")
def index():
    if "user" not in session:
        return redirect(url_for("login_page"))
    return render_template("index.html", current_user=session["user"])

@app.route("/register")
def register():
    return render_template("register.html")

@app.route("/admin")
def admin():
    return render_template("admin.html")

if __name__ == "__main__":
    app.run(debug=True)
