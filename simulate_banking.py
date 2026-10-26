"""
Smart Banking & Fund Transfer System - Local Interactive Simulator
Simulates the PL/SQL tables, triggers, and package procedures locally using SQLite & Python.
"""
import sqlite3
import sys
import io
from datetime import datetime

# Ensure standard UTF-8 stream output for Windows console
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

# Initialize in-memory or local database
conn = sqlite3.connect("banking_local.db")
cursor = conn.cursor()


# 1. Create Tables
cursor.executescript("""
DROP TABLE IF EXISTS AUDIT_LOGS;
DROP TABLE IF EXISTS TRANSACTIONS;
DROP TABLE IF EXISTS ACCOUNTS;

CREATE TABLE ACCOUNTS (
    account_no       INTEGER PRIMARY KEY AUTOINCREMENT,
    holder_name      TEXT NOT NULL,
    email            TEXT UNIQUE NOT NULL,
    phone            TEXT,
    account_type     TEXT DEFAULT 'SAVINGS' CHECK (account_type IN ('SAVINGS', 'CURRENT', 'SALARY')),
    balance          REAL DEFAULT 0.0 CHECK (balance >= 0),
    status           TEXT DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'DORMANT', 'FROZEN', 'CLOSED')),
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

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

CREATE TABLE AUDIT_LOGS (
    log_id           INTEGER PRIMARY KEY AUTOINCREMENT,
    account_no       INTEGER NOT NULL,
    action_type      TEXT NOT NULL,
    old_balance      REAL,
    new_balance      REAL,
    changed_by       TEXT DEFAULT 'SYSTEM_USER',
    changed_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Trigger: Simulating TRG_ACCOUNT_AUDIT
CREATE TRIGGER trg_account_audit_update
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
        'TRIGGER_TRG_ACCOUNT_AUDIT', 
        CURRENT_TIMESTAMP
    );
END;
""")
conn.commit()

# Reset auto-increment to 1001
cursor.execute("INSERT INTO sqlite_sequence (name, seq) VALUES ('ACCOUNTS', 1000);")
conn.commit()

def open_account(name, email, phone, acc_type, initial_deposit):
    cursor.execute("""
        INSERT INTO ACCOUNTS (holder_name, email, phone, account_type, balance, status)
        VALUES (?, ?, ?, ?, ?, 'ACTIVE')
    """, (name, email, phone, acc_type.upper(), initial_deposit))
    acc_no = cursor.lastrowid
    if initial_deposit > 0:
        cursor.execute("""
            INSERT INTO TRANSACTIONS (to_account, txn_type, amount, status, remarks)
            VALUES (?, 'DEPOSIT', ?, 'SUCCESS', 'Opening Deposit')
        """, (acc_no, initial_deposit))
    conn.commit()
    print(f"✔ [PACKAGE] Account Created: Acc #{acc_no} | {name} | Initial Bal: ₹{initial_deposit:,.2f}")
    return acc_no

def deposit(acc_no, amount, remarks='Cash Deposit'):
    cursor.execute("SELECT balance, status FROM ACCOUNTS WHERE account_no = ?", (acc_no,))
    row = cursor.fetchone()
    if not row or row[1] != 'ACTIVE':
        raise ValueError(f"Account {acc_no} is inactive or does not exist.")
    
    new_bal = row[0] + amount
    cursor.execute("UPDATE ACCOUNTS SET balance = ? WHERE account_no = ?", (new_bal, acc_no))
    cursor.execute("""
        INSERT INTO TRANSACTIONS (to_account, txn_type, amount, status, remarks)
        VALUES (?, 'DEPOSIT', ?, 'SUCCESS', ?)
    """, (acc_no, amount, remarks))
    conn.commit()
    print(f"✔ [DEPOSIT] Deposited ₹{amount:,.2f} into Acc #{acc_no} | New Balance: ₹{new_bal:,.2f}")

def withdraw(acc_no, amount, remarks='Cash Withdrawal'):
    cursor.execute("SELECT balance, status FROM ACCOUNTS WHERE account_no = ?", (acc_no,))
    row = cursor.fetchone()
    if not row or row[1] != 'ACTIVE':
        raise ValueError(f"Account {acc_no} is inactive or does not exist.")
    if row[0] < amount:
        raise ValueError(f"e_insufficient_funds: Available balance ₹{row[0]:,.2f} < Requested ₹{amount:,.2f}")
    
    new_bal = row[0] - amount
    cursor.execute("UPDATE ACCOUNTS SET balance = ? WHERE account_no = ?", (new_bal, acc_no))
    cursor.execute("""
        INSERT INTO TRANSACTIONS (from_account, txn_type, amount, status, remarks)
        VALUES (?, 'WITHDRAWAL', ?, 'SUCCESS', ?)
    """, (acc_no, amount, remarks))
    conn.commit()
    print(f"✔ [WITHDRAW] Debited ₹{amount:,.2f} from Acc #{acc_no} | New Balance: ₹{new_bal:,.2f}")

def transfer_funds(from_acc, to_acc, amount, remarks='Fund Transfer'):
    if from_acc == to_acc:
        raise ValueError("e_same_account: Sender and Receiver cannot be same.")
    
    # Check sender
    cursor.execute("SELECT balance, status FROM ACCOUNTS WHERE account_no = ?", (from_acc,))
    s_row = cursor.fetchone()
    if not s_row or s_row[1] != 'ACTIVE':
        raise ValueError(f"e_account_inactive: Sender {from_acc} is invalid.")
    if s_row[0] < amount:
        # Record failed txn
        cursor.execute("""
            INSERT INTO TRANSACTIONS (from_account, to_account, txn_type, amount, status, remarks)
            VALUES (?, ?, 'TRANSFER', ?, 'FAILED', 'Insufficient balance')
        """, (from_acc, to_acc, amount))
        conn.commit()
        raise ValueError(f"e_insufficient_funds: Sender Acc #{from_acc} has ₹{s_row[0]:,.2f}, needs ₹{amount:,.2f}")
    
    # Check receiver
    cursor.execute("SELECT status FROM ACCOUNTS WHERE account_no = ?", (to_acc,))
    r_row = cursor.fetchone()
    if not r_row or r_row[0] != 'ACTIVE':
        raise ValueError(f"e_account_inactive: Receiver {to_acc} is invalid.")
    
    # Atomic transaction
    cursor.execute("UPDATE ACCOUNTS SET balance = balance - ? WHERE account_no = ?", (amount, from_acc))
    cursor.execute("UPDATE ACCOUNTS SET balance = balance + ? WHERE account_no = ?", (amount, to_acc))
    cursor.execute("""
        INSERT INTO TRANSACTIONS (from_account, to_account, txn_type, amount, status, remarks)
        VALUES (?, ?, 'TRANSFER', ?, 'SUCCESS', ?)
    """, (from_acc, to_acc, amount, remarks))
    conn.commit()
    print(f"✔ [TRANSFER] Transferred ₹{amount:,.2f} from Acc #{from_acc} -> Acc #{to_acc}")

def apply_monthly_interest(annual_rate=4.5):
    print(f"\n--- [CURSOR] APPLYING MONTHLY INTEREST ({annual_rate}% P.A.) ---")
    cursor.execute("SELECT account_no, balance FROM ACCOUNTS WHERE account_type = 'SAVINGS' AND status = 'ACTIVE' AND balance > 0")
    savings_accounts = cursor.fetchall()
    
    total_paid = 0
    for acc_no, bal in savings_accounts:
        monthly_interest = round((bal * (annual_rate / 100)) / 12, 2)
        if monthly_interest > 0:
            cursor.execute("UPDATE ACCOUNTS SET balance = balance + ? WHERE account_no = ?", (monthly_interest, acc_no))
            cursor.execute("""
                INSERT INTO TRANSACTIONS (to_account, txn_type, amount, status, remarks)
                VALUES (?, 'INTEREST', ?, 'SUCCESS', ?)
            """, (acc_no, monthly_interest, f"Monthly Interest @ {annual_rate}%"))
            total_paid += monthly_interest
            print(f"  -> Acc #{acc_no} credited with interest: ₹{monthly_interest:,.2f}")
    conn.commit()
    print(f"✔ Interest batch completed. Total interest distributed: ₹{total_paid:,.2f}\n")

def print_mini_statement(acc_no):
    cursor.execute("SELECT holder_name, balance FROM ACCOUNTS WHERE account_no = ?", (acc_no,))
    acc = cursor.fetchone()
    if not acc:
        return
    print("-" * 75)
    print(f" MINI STATEMENT | Acc #{acc_no} ({acc[0]}) | Current Balance: ₹{acc[1]:,.2f}")
    print("-" * 75)
    print(f"{'TXN ID':<8} {'TYPE':<12} {'AMOUNT':<14} {'STATUS':<10} {'REMARKS'}")
    print("-" * 75)
    cursor.execute("""
        SELECT txn_id, txn_type, amount, status, remarks 
        FROM TRANSACTIONS 
        WHERE from_account = ? OR to_account = ? 
        ORDER BY txn_id DESC LIMIT 5
    """, (acc_no, acc_no))
    for t in cursor.fetchall():
        print(f"#{t[0]:<7} {t[1]:<12} ₹{t[2]:<13,.2f} {t[3]:<10} {t[4]}")
    print("-" * 75 + "\n")

if __name__ == "__main__":
    print("=" * 75)
    print("   SMART BANKING & FUND TRANSFER SYSTEM (PL/SQL SIMULATION)")
    print("=" * 75)
    
    # 1. Seed Accounts
    print("\n--- 1. Creating Sample Bank Accounts ---")
    a1 = open_account("Rahul Sharma", "rahul@example.com", "9876543210", "SAVINGS", 25000.0)
    a2 = open_account("Priya Patel", "priya@example.com", "9823456781", "SALARY", 50000.0)
    a3 = open_account("Amit Verma", "amit@example.com", "9811223344", "CURRENT", 100000.0)
    a4 = open_account("Neha Singh", "neha@example.com", "9899887766", "SAVINGS", 1500.0)
    
    # 2. Operations
    print("\n--- 2. Executing Banking Transactions ---")
    deposit(a1, 5000.0, "Cash Deposit via CDM")
    withdraw(a2, 2000.0, "ATM Cash Withdrawal")
    transfer_funds(a1, a2, 3000.0, "Rent Payment")
    
    # 3. Exception Test
    print("\n--- 3. Testing Exception Handling (Insufficient Funds) ---")
    try:
        transfer_funds(a4, a1, 50000.0, "Overdraw attempt")
    except Exception as e:
        print(f"✔ Caught Expected Error: {e}")
        
    # 4. Monthly Interest Cursor
    apply_monthly_interest(4.5)
    
    # 5. Statements
    print_mini_statement(a1)
    print_mini_statement(a2)
    
    # 6. Check Trigger Audit Log
    print("=" * 75)
    print("   AUTOMATED AUDIT TRAIL (Generated by Trigger TRG_ACCOUNT_AUDIT)")
    print("=" * 75)
    print(f"{'LOG ID':<8} {'ACC NO':<10} {'ACTION TYPE':<16} {'OLD BAL':<14} {'NEW BAL':<14} {'TRIGGER'}")
    print("-" * 75)
    cursor.execute("SELECT log_id, account_no, action_type, old_balance, new_balance, changed_by FROM AUDIT_LOGS")
    for row in cursor.fetchall():
        print(f"#{row[0]:<7} Acc #{row[1]:<6} {row[2]:<16} ₹{row[3]:<13,.2f} ₹{row[4]:<13,.2f} {row[5]}")
    print("=" * 75)
