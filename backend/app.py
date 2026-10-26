"""
Smart Banking & ADBMS Enterprise Fund Transfer System - Backend Flask Server
Provides RESTful APIs for both Core Banking PL/SQL and Advanced DBMS Features.
"""
import os
import sqlite3
from flask import Flask, jsonify, request, send_from_directory
from backend.database import init_database, get_connection
from backend.banking_engine import BankingEngine

FRONTEND_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "frontend")

app = Flask(__name__, static_folder=FRONTEND_DIR, static_url_path="")

# Ensure Database is initialized on startup
init_database()

# -----------------------------------------------------------------------------
# Frontend Routes
# -----------------------------------------------------------------------------
@app.route("/")
def serve_index():
    return send_from_directory(FRONTEND_DIR, "index.html")

@app.route("/<path:path>")
def serve_static(path):
    if os.path.exists(os.path.join(FRONTEND_DIR, path)):
        return send_from_directory(FRONTEND_DIR, path)
    return send_from_directory(FRONTEND_DIR, "index.html")

# -----------------------------------------------------------------------------
# Core Banking API Endpoints
# -----------------------------------------------------------------------------
@app.route("/api/stats", methods=["GET"])
def api_stats():
    return jsonify({"success": True, "data": BankingEngine.get_stats()})

@app.route("/api/accounts", methods=["GET"])
def api_get_accounts():
    accounts = BankingEngine.get_all_accounts()
    return jsonify({"success": True, "data": accounts})

@app.route("/api/accounts", methods=["POST"])
def api_create_account():
    data = request.json or {}
    try:
        name = data.get("holder_name", "")
        email = data.get("email", "")
        phone = data.get("phone", "")
        acc_type = data.get("account_type", "SAVINGS")
        initial_deposit = float(data.get("initial_deposit", 0.0))
        branch_code = data.get("branch_code", "BR-DEL-01")

        if not name or not email or not phone:
            return jsonify({"success": False, "error": "Name, Email, and Phone are required."}), 400

        address = {"street": "12 Main St", "city": "Delhi", "state": "Delhi", "pincode": "110001"}
        kyc = {"doc_type": "AADHAAR", "doc_number": "4589-1234-9012"}

        result = BankingEngine.open_account_ordbms(name, email, [phone], address, kyc, branch_code, acc_type, initial_deposit)
        return jsonify({"success": True, "data": result, "message": f"Account #{result['account_no']} created successfully!"})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 400

@app.route("/api/accounts/<int:account_no>", methods=["GET"])
def api_get_account(account_no):
    acc = BankingEngine.get_account_by_id(account_no)
    if not acc:
        return jsonify({"success": False, "error": f"Account #{account_no} not found"}), 404
    return jsonify({"success": True, "data": acc})

@app.route("/api/deposit", methods=["POST"])
def api_deposit():
    data = request.json or {}
    try:
        acc_no = int(data.get("account_no", 0))
        amount = float(data.get("amount", 0.0))
        remarks = data.get("remarks", "Cash Deposit")
        result = BankingEngine.deposit(acc_no, amount, remarks)
        return jsonify({"success": True, "data": result, "message": f"₹{amount:,.2f} credited to Acc #{acc_no}."})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 400

@app.route("/api/withdraw", methods=["POST"])
def api_withdraw():
    data = request.json or {}
    try:
        acc_no = int(data.get("account_no", 0))
        amount = float(data.get("amount", 0.0))
        remarks = data.get("remarks", "Cash Withdrawal")
        result = BankingEngine.withdraw(acc_no, amount, remarks)
        return jsonify({"success": True, "data": result, "message": f"₹{amount:,.2f} debited from Acc #{acc_no}."})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 400

@app.route("/api/transfer", methods=["POST"])
def api_transfer():
    data = request.json or {}
    try:
        from_acc = int(data.get("from_account", 0))
        to_acc = int(data.get("to_account", 0))
        amount = float(data.get("amount", 0.0))
        remarks = data.get("remarks", "Fund Transfer")
        result = BankingEngine.transfer_funds(from_acc, to_acc, amount, remarks)
        return jsonify({
            "success": True, 
            "data": result, 
            "message": f"Atomic Transfer of Rs. {amount:,.2f} from Acc #{from_acc} to Acc #{to_acc} successful [COMMIT]!"
        })
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 400

@app.route("/api/interest", methods=["POST"])
def api_interest():
    data = request.json or {}
    try:
        rate = float(data.get("rate", 4.5))
        result = BankingEngine.bulk_apply_monthly_interest(rate)
        return jsonify({
            "success": True,
            "data": result,
            "message": f"Batch Finished: Rs. {result['total_interest_paid']:,.2f} credited across {result['accounts_credited']} Accounts."
        })
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 400

@app.route("/api/transactions", methods=["GET"])
def api_transactions():
    limit = int(request.args.get("limit", 50))
    txns = BankingEngine.get_transactions(limit)
    return jsonify({"success": True, "data": txns})

@app.route("/api/audit-logs", methods=["GET"])
def api_audit_logs():
    limit = int(request.args.get("limit", 50))
    logs = BankingEngine.get_audit_logs(limit)
    return jsonify({"success": True, "data": logs})

# -----------------------------------------------------------------------------
# ADBMS Advanced Endpoints
# -----------------------------------------------------------------------------
@app.route("/api/adbms/fraud-alerts", methods=["GET"])
def api_adbms_fraud_alerts():
    alerts = BankingEngine.get_fraud_alerts()
    return jsonify({"success": True, "data": alerts})

@app.route("/api/adbms/fraud-alerts/test", methods=["POST"])
def api_adbms_test_fraud():
    data = request.json or {}
    acc_no = int(data.get("account_no", 1004))
    amount = float(data.get("amount", 999999.0))
    BankingEngine.log_fraud_alert_autonomous(
        acc_no, "HIGH",
        f"Simulated Autonomous Security Violation: Overdraft attempt of ₹{amount:,.2f}",
        amount
    )
    return jsonify({"success": True, "message": "Autonomous fraud log committed independently of transaction state."})

@app.route("/api/adbms/distributed-txns", methods=["GET", "POST"])
def api_adbms_distributed():
    if request.method == "POST":
        data = request.json or {}
        try:
            source_b = data.get("source_branch", "BR-DEL-01")
            target_b = data.get("target_branch", "BR-BLR-01")
            from_acc = int(data.get("from_account", 1001))
            to_acc = int(data.get("to_account", 1003))
            amount = float(data.get("amount", 1000.0))
            sim_fail = data.get("simulate_fail", "NONE")
            result = BankingEngine.simulate_distributed_transfer(source_b, target_b, from_acc, to_acc, amount, sim_fail)
            return jsonify({"success": True, "data": result, "message": f"Distributed 2PC Transaction Committed! Global XID: {result['global_xid']}"})
        except Exception as e:
            return jsonify({"success": False, "error": str(e)}), 400
    else:
        dtxns = BankingEngine.get_distributed_txns()
        return jsonify({"success": True, "data": dtxns})

@app.route("/api/adbms/partitions/transactions", methods=["GET"])
def api_adbms_part_txns():
    part = request.args.get("partition", "ALL")
    txns = BankingEngine.get_partitioned_transactions(part)
    return jsonify({"success": True, "data": txns, "partition": part})

@app.route("/api/adbms/partitions/accounts", methods=["GET"])
def api_adbms_part_accs():
    part = request.args.get("partition", "ALL")
    accs = BankingEngine.get_partitioned_accounts(part)
    return jsonify({"success": True, "data": accs, "partition": part})

@app.route("/api/adbms/mviews/branches", methods=["GET"])
def api_adbms_mv_branches():
    rows = BankingEngine.get_branch_summary_mview()
    return jsonify({"success": True, "data": rows})

@app.route("/api/adbms/mviews/networth", methods=["GET"])
def api_adbms_mv_networth():
    rows = BankingEngine.get_customer_networth_mview()
    return jsonify({"success": True, "data": rows})

@app.route("/api/adbms/mviews/refresh", methods=["POST"])
def api_adbms_mv_refresh():
    res = BankingEngine.refresh_all_mviews()
    return jsonify({"success": True, "data": res, "message": "Materialized Views fast-refreshed successfully."})

@app.route("/api/adbms/bulk/fee", methods=["POST"])
def api_adbms_bulk_fee():
    data = request.json or {}
    try:
        fee = float(data.get("fee_amount", 150.0))
        tier = float(data.get("min_tier", 2000.0))
        res = BankingEngine.bulk_deduct_service_fee(fee, tier)
        return jsonify({"success": True, "data": res, "message": f"Bulk FORALL applied: ₹{res['total_fees_collected']:,.2f} collected from {res['accounts_charged']} accounts in {res['elapsed_ms']}ms."})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 400

@app.route("/api/adbms/olap", methods=["GET"])
def api_adbms_olap():
    olap = BankingEngine.get_olap_analytics()
    return jsonify({"success": True, "data": olap})

@app.route("/api/execute-sql", methods=["POST"])
def api_execute_sql():
    data = request.json or {}
    query = (data.get("query") or "").strip()
    if not query:
        return jsonify({"success": False, "error": "SQL query cannot be empty."}), 400

    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute(query)
        if query.upper().startswith("SELECT"):
            columns = [desc[0] for desc in cursor.description] if cursor.description else []
            rows = [dict(zip(columns, row)) for row in cursor.fetchall()]
            return jsonify({"success": True, "type": "SELECT", "columns": columns, "rows": rows, "count": len(rows)})
        else:
            conn.commit()
            return jsonify({"success": True, "type": "DML", "message": f"Statement executed successfully ({cursor.rowcount} rows affected)."})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 400
    finally:
        conn.close()

@app.route("/api/reset", methods=["POST"])
def api_reset():
    try:
        init_database()
        return jsonify({"success": True, "message": "Database reset to ADBMS initial multi-branch dataset."})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

def start_server(port=5000):
    print(f"\n=======================================================")
    print(f"  ADBMS & PL/SQL Smart Banking Server Running on:")
    print(f"  ➜ http://127.0.0.1:{port}")
    print(f"=======================================================\n")
    app.run(host="0.0.0.0", port=port, debug=False)

if __name__ == "__main__":
    start_server(5000)
