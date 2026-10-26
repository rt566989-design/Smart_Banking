import os
import sqlite3
from flask import Flask, render_template, request, jsonify

app = Flask(__name__)
DB_PATH = os.path.join(os.path.dirname(__file__), "banking_web.db")

def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db()
    cursor = conn.cursor()
    cursor.executescript("""
        DROP TABLE IF EXISTS AUDIT_LOGS;
        DROP TABLE IF EXISTS TRANSACTIONS;
        DROP TABLE IF EXISTS ACCOUNTS;

        CREATE TABLE ACCOUNTS (
            account_no   INTEGER PRIMARY KEY AUTOINCREMENT,
            holder_name  TEXT NOT NULL,
            email        TEXT UNIQUE NOT NULL,
            phone        TEXT,
            account_type TEXT DEFAULT 'SAVINGS',
            balance      REAL DEFAULT 0.0,
            status       TEXT DEFAULT 'ACTIVE',
            created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE TRANSACTIONS (
            txn_id       INTEGER PRIMARY KEY AUTOINCREMENT,
            from_account INTEGER,
            to_account   INTEGER,
            txn_type     TEXT NOT NULL,
            amount       REAL NOT NULL,
            txn_date     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            status       TEXT DEFAULT 'SUCCESS',
            remarks      TEXT
        );

        CREATE TABLE AUDIT_LOGS (
            log_id       INTEGER PRIMARY KEY AUTOINCREMENT,
            account_no   INTEGER NOT NULL,
            action_type  TEXT NOT NULL,
            old_balance  REAL,
            new_balance  REAL,
            changed_by   TEXT DEFAULT 'TRG_ACCOUNT_AUDIT',
            changed_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TRIGGER trg_audit
        AFTER UPDATE OF balance ON ACCOUNTS
        FOR EACH ROW
        BEGIN
            INSERT INTO AUDIT_LOGS (account_no, action_type, old_balance, new_balance, changed_by, changed_at)
            VALUES (
                NEW.account_no,
                CASE WHEN NEW.balance > OLD.balance THEN 'CREDIT_UPDATE' ELSE 'DEBIT_UPDATE' END,
                OLD.balance,
                NEW.balance,
                'TRG_ACCOUNT_AUDIT',
                CURRENT_TIMESTAMP
            );
        END;
    """)
    cursor.execute("INSERT INTO sqlite_sequence (name, seq) VALUES ('ACCOUNTS', 1000);")
    
    # Initial seed data
    users = [
        ('Rahul Sharma', 'rahul@example.com', '9876543210', 'SAVINGS', 25000.0),
        ('Priya Patel', 'priya@example.com', '9823456781', 'SALARY', 50000.0),
        ('Amit Verma', 'amit@example.com', '9811223344', 'CURRENT', 100000.0),
        ('Neha Singh', 'neha@example.com', '9899887766', 'SAVINGS', 1500.0)
    ]
    for name, email, phone, acc_type, bal in users:
        cursor.execute("INSERT INTO ACCOUNTS (holder_name, email, phone, account_type, balance, status) VALUES (?, ?, ?, ?, ?, 'ACTIVE')",
                       (name, email, phone, acc_type, bal))
        acc_no = cursor.lastrowid
        cursor.execute("INSERT INTO TRANSACTIONS (to_account, txn_type, amount, status, remarks) VALUES (?, 'DEPOSIT', ?, 'SUCCESS', 'Opening Deposit')",
                       (acc_no, bal))
    conn.commit()
    conn.close()

# Ensure DB is created
init_db()

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/api/accounts", methods=["GET"])
def get_accounts():
    conn = get_db()
    accounts = conn.execute("SELECT * FROM ACCOUNTS ORDER BY account_no ASC").fetchall()
    conn.close()
    return jsonify([dict(ix) for ix in accounts])

@app.route("/api/transactions", methods=["GET"])
def get_transactions():
    conn = get_db()
    txns = conn.execute("SELECT * FROM TRANSACTIONS ORDER BY txn_id DESC LIMIT 15").fetchall()
    conn.close()
    return jsonify([dict(ix) for ix in txns])

@app.route("/api/audits", methods=["GET"])
def get_audits():
    conn = get_db()
    logs = conn.execute("SELECT * FROM AUDIT_LOGS ORDER BY log_id DESC LIMIT 15").fetchall()
    conn.close()
    return jsonify([dict(ix) for ix in logs])

@app.route("/api/deposit", methods=["POST"])
def deposit():
    data = request.json or {}
    acc_no = int(data.get("account_no", 0))
    amount = float(data.get("amount", 0))
    remarks = data.get("remarks", "Cash Deposit")

    if amount <= 0:
        return jsonify({"success": False, "error": "Amount must be > 0"}), 400

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("UPDATE ACCOUNTS SET balance = balance + ? WHERE account_no = ?", (amount, acc_no))
    cursor.execute("INSERT INTO TRANSACTIONS (to_account, txn_type, amount, status, remarks) VALUES (?, 'DEPOSIT', ?, 'SUCCESS', ?)",
                   (acc_no, amount, remarks))
    conn.commit()
    conn.close()
    return jsonify({"success": True, "message": f"₹{amount:,.2f} deposited to Acc {acc_no}"})

@app.route("/api/withdraw", methods=["POST"])
def withdraw():
    data = request.json or {}
    acc_no = int(data.get("account_no", 0))
    amount = float(data.get("amount", 0))
    remarks = data.get("remarks", "Cash Withdrawal")

    if amount <= 0:
        return jsonify({"success": False, "error": "Amount must be > 0"}), 400

    conn = get_db()
    cursor = conn.cursor()
    acc = cursor.execute("SELECT balance FROM ACCOUNTS WHERE account_no = ?", (acc_no,)).fetchone()
    if not acc:
        conn.close()
        return jsonify({"success": False, "error": "Account not found"}), 404

    if acc["balance"] < amount:
        conn.close()
        return jsonify({"success": False, "error": f"ORA-20002: Insufficient balance. Available: ₹{acc['balance']:,.2f}"}), 400

    cursor.execute("UPDATE ACCOUNTS SET balance = balance - ? WHERE account_no = ?", (amount, acc_no))
    cursor.execute("INSERT INTO TRANSACTIONS (from_account, txn_type, amount, status, remarks) VALUES (?, 'WITHDRAWAL', ?, 'SUCCESS', ?)",
                   (acc_no, amount, remarks))
    conn.commit()
    conn.close()
    return jsonify({"success": True, "message": f"₹{amount:,.2f} withdrawn from Acc {acc_no}"})

@app.route("/api/transfer", methods=["POST"])
def transfer():
    data = request.json or {}
    from_acc = int(data.get("from_account", 0))
    to_acc = int(data.get("to_account", 0))
    amount = float(data.get("amount", 0))
    remarks = data.get("remarks", "Fund Transfer")

    if from_acc == to_acc:
        return jsonify({"success": False, "error": "ORA-20005: Sender & receiver cannot be the same"}), 400
    if amount <= 0:
        return jsonify({"success": False, "error": "Amount must be > 0"}), 400

    conn = get_db()
    cursor = conn.cursor()
    s_acc = cursor.execute("SELECT balance FROM ACCOUNTS WHERE account_no = ?", (from_acc,)).fetchone()
    r_acc = cursor.execute("SELECT balance FROM ACCOUNTS WHERE account_no = ?", (to_acc,)).fetchone()

    if not s_acc or not r_acc:
        conn.close()
        return jsonify({"success": False, "error": "ORA-20003: Invalid sender or receiver account"}), 404

    if s_acc["balance"] < amount:
        cursor.execute("INSERT INTO TRANSACTIONS (from_account, to_account, txn_type, amount, status, remarks) VALUES (?, ?, 'TRANSFER', ?, 'FAILED', 'ORA-20002: Insufficient balance')",
                       (from_acc, to_acc, amount))
        conn.commit()
        conn.close()
        return jsonify({"success": False, "error": f"ORA-20002: Insufficient funds in Acc #{from_acc}"}), 400

    # Atomic transfer
    cursor.execute("UPDATE ACCOUNTS SET balance = balance - ? WHERE account_no = ?", (amount, from_acc))
    cursor.execute("UPDATE ACCOUNTS SET balance = balance + ? WHERE account_no = ?", (amount, to_acc))
    cursor.execute("INSERT INTO TRANSACTIONS (from_account, to_account, txn_type, amount, status, remarks) VALUES (?, ?, 'TRANSFER', ?, 'SUCCESS', ?)",
                   (from_acc, to_acc, amount, remarks))
    conn.commit()
    conn.close()
    return jsonify({"success": True, "message": f"Transferred ₹{amount:,.2f} from #{from_acc} to #{to_acc}"})

@app.route("/api/interest", methods=["POST"])
def apply_interest():
    data = request.json or {}
    rate = float(data.get("rate", 4.5))

    conn = get_db()
    cursor = conn.cursor()
    savings = cursor.execute("SELECT account_no, balance FROM ACCOUNTS WHERE account_type = 'SAVINGS' AND status = 'ACTIVE'").fetchall()
    total_distributed = 0
    count = 0

    for s in savings:
        interest = round((s["balance"] * (rate / 100)) / 12, 2)
        if interest > 0:
            cursor.execute("UPDATE ACCOUNTS SET balance = balance + ? WHERE account_no = ?", (interest, s["account_no"]))
            cursor.execute("INSERT INTO TRANSACTIONS (to_account, txn_type, amount, status, remarks) VALUES (?, 'INTEREST', ?, 'SUCCESS', ?)",
                           (s["account_no"], interest, f"Monthly Interest @ {rate}%"))
            total_distributed += interest
            count += 1

    conn.commit()
    conn.close()
    return jsonify({
        "success": True, 
        "message": f"Cursor completed: ₹{total_distributed:,.2f} credited across {count} accounts"
    })

@app.route("/api/reset", methods=["POST"])
def reset():
    init_db()
    return jsonify({"success": True, "message": "Database reset to initial seed state!"})

if __name__ == "__main__":
    print("Starting Smart Banking Web UI on http://127.0.0.1:5000 ...")
    app.run(port=5000, debug=False)
