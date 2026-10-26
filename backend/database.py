"""
Database Engine & PL/SQL Simulation Core
Handles SQLite connection, schema setup, triggers, and transactions.
"""
import sqlite3
import os

DB_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "smart_banking.db")

def get_connection():
    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row
    return conn

def init_database():
    """Initializes tables, triggers, and seeds default accounts."""
    conn = get_connection()
    cursor = conn.cursor()

    cursor.executescript("""
        DROP TABLE IF EXISTS AUDIT_LOGS;
        DROP TABLE IF EXISTS TRANSACTIONS;
        DROP TABLE IF EXISTS ACCOUNTS;

        -- 1. ACCOUNTS TABLE
        CREATE TABLE ACCOUNTS (
            account_no       INTEGER PRIMARY KEY AUTOINCREMENT,
            holder_name      TEXT NOT NULL,
            email            TEXT UNIQUE NOT NULL,
            phone            TEXT NOT NULL,
            account_type     TEXT DEFAULT 'SAVINGS' CHECK (account_type IN ('SAVINGS', 'CURRENT', 'SALARY')),
            balance          REAL DEFAULT 0.0 CHECK (balance >= 0),
            status           TEXT DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'DORMANT', 'FROZEN', 'CLOSED')),
            created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        -- 2. TRANSACTIONS TABLE
        CREATE TABLE TRANSACTIONS (
            txn_id           INTEGER PRIMARY KEY AUTOINCREMENT,
            from_account     INTEGER,
            to_account       INTEGER,
            txn_type         TEXT NOT NULL CHECK (txn_type IN ('DEPOSIT', 'WITHDRAWAL', 'TRANSFER', 'INTEREST')),
            amount           REAL NOT NULL CHECK (amount > 0),
            txn_date         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            status           TEXT DEFAULT 'SUCCESS' CHECK (status IN ('SUCCESS', 'FAILED')),
            remarks          TEXT,
            FOREIGN KEY(from_account) REFERENCES ACCOUNTS(account_no),
            FOREIGN KEY(to_account) REFERENCES ACCOUNTS(account_no)
        );

        -- 3. AUDIT_LOGS TABLE (Trigger target)
        CREATE TABLE AUDIT_LOGS (
            log_id           INTEGER PRIMARY KEY AUTOINCREMENT,
            account_no       INTEGER NOT NULL,
            action_type      TEXT NOT NULL,
            old_balance      REAL,
            new_balance      REAL,
            changed_by       TEXT DEFAULT 'TRIGGER_TRG_ACCOUNT_AUDIT',
            changed_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        -- 4. TRIGGER: Automated Balance & Audit Trail Tracker
        CREATE TRIGGER TRG_ACCOUNT_AUDIT
        AFTER UPDATE OF balance ON ACCOUNTS
        FOR EACH ROW
        BEGIN
            INSERT INTO AUDIT_LOGS (account_no, action_type, old_balance, new_balance, changed_by, changed_at)
            VALUES (
                NEW.account_no,
                CASE 
                    WHEN NEW.balance > OLD.balance THEN 'CREDIT_UPDATE'
                    ELSE 'DEBIT_UPDATE'
                END,
                OLD.balance,
                NEW.balance,
                'TRG_ACCOUNT_AUDIT',
                CURRENT_TIMESTAMP
            );
        END;
    """)

    # Seed starting sequence from 1001
    cursor.execute("INSERT INTO sqlite_sequence (name, seq) VALUES ('ACCOUNTS', 1000);")
    cursor.execute("INSERT INTO sqlite_sequence (name, seq) VALUES ('TRANSACTIONS', 50000);")

    # Seed 4 realistic accounts
    sample_accounts = [
        ('Rahul Sharma', 'rahul.sharma@example.com', '+91 98765 43210', 'SAVINGS', 25000.0),
        ('Priya Patel', 'priya.patel@example.com', '+91 98234 56781', 'SALARY', 50000.0),
        ('Amit Verma', 'amit.verma@example.com', '+91 98112 23344', 'CURRENT', 100000.0),
        ('Neha Singh', 'neha.singh@example.com', '+91 98998 87766', 'SAVINGS', 1500.0)
    ]

    for name, email, phone, acc_type, bal in sample_accounts:
        cursor.execute("""
            INSERT INTO ACCOUNTS (holder_name, email, phone, account_type, balance, status)
            VALUES (?, ?, ?, ?, ?, 'ACTIVE')
        """, (name, email, phone, acc_type, bal))
        acc_no = cursor.lastrowid
        cursor.execute("""
            INSERT INTO TRANSACTIONS (to_account, txn_type, amount, status, remarks)
            VALUES (?, 'DEPOSIT', ?, 'SUCCESS', 'Opening Deposit')
        """, (acc_no, bal))

    conn.commit()
    conn.close()
