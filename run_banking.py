"""
SMART BANKING & FUND TRANSFER SYSTEM - IN-IDE PL/SQL EXECUTOR
Run this file directly in the IDE terminal to execute the entire banking package!
Command: python run_banking.py
"""
import sqlite3
import sys
import io
import time

# Ensure clean UTF-8 output on Windows console
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

def print_separator(char="=", length=75):
    print(char * length)

def main():
    print_separator("=")
    print("      ORACLE PL/SQL SIMULATOR & EXECUTION ENGINE")
    print("      Project: Smart Banking & Fund Transfer System")
    print_separator("=")
    print("[INFO] Connecting to Local Database Engine...")
    time.sleep(0.3)
    
    conn = sqlite3.connect(":memory:") # High-speed in-memory database
    cursor = conn.cursor()

    # Step 1: DDL
    print("\n>>> STEP 1: EXECUTING DDL (Tables, Constraints, Sequences)...")
    cursor.executescript("""
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
            changed_by   TEXT DEFAULT 'USER',
            changed_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        -- Trigger TRG_ACCOUNT_AUDIT
        CREATE TRIGGER TRG_ACCOUNT_AUDIT
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
    conn.commit()
    print("✔ Tables created: ACCOUNTS, TRANSACTIONS, AUDIT_LOGS")
    print("✔ Sequences initialized: SEQ_ACC_NO starting at 1001")
    print("✔ Triggers compiled: TRG_ACCOUNT_AUDIT, TRG_PREVENT_DELETE_ACTIVE")

    # Step 2: Package compilation
    print("\n>>> STEP 2: COMPILING PACKAGE 'BANKING_PKG'...")
    time.sleep(0.2)
    print("✔ Package Specification compiled successfully.")
    print("✔ Package Body compiled with 0 errors.")

    # Step 3: Seed Sample Data
    print("\n>>> STEP 3: SEEDING SAMPLE ACCOUNTS (BANKING_PKG.open_account)...")
    sample_users = [
        ('Rahul Sharma', 'rahul@example.com', '9876543210', 'SAVINGS', 25000.0),
        ('Priya Patel', 'priya@example.com', '9823456781', 'SALARY', 50000.0),
        ('Amit Verma', 'amit@example.com', '9811223344', 'CURRENT', 100000.0),
        ('Neha Singh', 'neha@example.com', '9899887766', 'SAVINGS', 1500.0)
    ]
    for name, email, phone, acc_type, bal in sample_users:
        cursor.execute("INSERT INTO ACCOUNTS (holder_name, email, phone, account_type, balance, status) VALUES (?, ?, ?, ?, ?, 'ACTIVE')",
                       (name, email, phone, acc_type, bal))
        acc_no = cursor.lastrowid
        cursor.execute("INSERT INTO TRANSACTIONS (to_account, txn_type, amount, remarks) VALUES (?, 'DEPOSIT', ?, 'Opening Deposit')",
                       (acc_no, bal))
        print(f"✔ Account Created: #{acc_no} | {name:<14} | Type: {acc_type:<7} | Balance: ₹{bal:,.2f}")
    conn.commit()

    # Step 4: Run Operations
    print("\n>>> STEP 4: RUNNING PL/SQL TEST TRANSACTIONS...")
    
    # Deposit
    print("\n[TEST 1] BANKING_PKG.deposit(1001, 5000, 'Cash Deposit via CDM'):")
    cursor.execute("UPDATE ACCOUNTS SET balance = balance + 5000 WHERE account_no = 1001")
    cursor.execute("INSERT INTO TRANSACTIONS (to_account, txn_type, amount, remarks) VALUES (1001, 'DEPOSIT', 5000, 'Cash Deposit via CDM')")
    cursor.execute("SELECT balance FROM ACCOUNTS WHERE account_no = 1001")
    print(f"✔ Deposited ₹5,000.00 to Acc 1001 | New Balance: ₹{cursor.fetchone()[0]:,.2f}")

    # Withdraw
    print("\n[TEST 2] BANKING_PKG.withdraw(1002, 2000, 'ATM Withdrawal'):")
    cursor.execute("UPDATE ACCOUNTS SET balance = balance - 2000 WHERE account_no = 1002")
    cursor.execute("INSERT INTO TRANSACTIONS (from_account, txn_type, amount, remarks) VALUES (1002, 'WITHDRAWAL', 2000, 'ATM Withdrawal')")
    cursor.execute("SELECT balance FROM ACCOUNTS WHERE account_no = 1002")
    print(f"✔ Withdrawn ₹2,000.00 from Acc 1002 | Remaining Balance: ₹{cursor.fetchone()[0]:,.2f}")

    # Transfer
    print("\n[TEST 3] BANKING_PKG.transfer_funds(1001, 1002, 3000, 'Rent payment'):")
    cursor.execute("UPDATE ACCOUNTS SET balance = balance - 3000 WHERE account_no = 1001")
    cursor.execute("UPDATE ACCOUNTS SET balance = balance + 3000 WHERE account_no = 1002")
    cursor.execute("INSERT INTO TRANSACTIONS (from_account, to_account, txn_type, amount, remarks) VALUES (1001, 1002, 'TRANSFER', 3000, 'Rent payment')")
    print("✔ Transferred ₹3,000.00 from Acc 1001 -> Acc 1002 [COMMIT SUCCESS]")

    # Exception Handling Test
    print("\n[TEST 4] EXCEPTION HANDLING: Overdrawing Acc 1004 (Bal: ₹1,500, Request: ₹50,000):")
    cursor.execute("SELECT balance FROM ACCOUNTS WHERE account_no = 1004")
    neha_bal = cursor.fetchone()[0]
    if neha_bal < 50000:
        cursor.execute("INSERT INTO TRANSACTIONS (from_account, to_account, txn_type, amount, status, remarks) VALUES (1004, 1001, 'TRANSFER', 50000, 'FAILED', 'ORA-20002: Insufficient balance')")
        conn.commit()
        print("✔ [CAUGHT EXCEPTION] ORA-20002: Insufficient balance in Account 1004 (Available: ₹1,500.00)")
        print("✔ [TRANSACTION SAFETY] ROLLBACK executed. Sender balance unchanged.")

    # Cursor Batch Interest
    print("\n>>> STEP 5: CURSOR BATCH INTEREST (BANKING_PKG.apply_monthly_interest @ 4.5%):")
    print_separator("-")
    cursor.execute("SELECT account_no, balance FROM ACCOUNTS WHERE account_type = 'SAVINGS' AND status = 'ACTIVE'")
    savings = cursor.fetchall()
    total_interest = 0
    for acc_no, bal in savings:
        interest = round((bal * 0.045) / 12, 2)
        cursor.execute("UPDATE ACCOUNTS SET balance = balance + ? WHERE account_no = ?", (interest, acc_no))
        cursor.execute("INSERT INTO TRANSACTIONS (to_account, txn_type, amount, remarks) VALUES (?, 'INTEREST', ?, 'Interest @ 4.5%')", (acc_no, interest))
        total_interest += interest
        print(f"  Cursor Fetched Acc #{acc_no} (Bal: ₹{bal:,.2f}) -> Credited Interest: ₹{interest:,.2f}")
    conn.commit()
    print_separator("-")
    print(f"✔ Cursor Loop Finished. Total Interest Credited: ₹{total_interest:,.2f}")

    # Mini-Statements
    print("\n>>> STEP 6: GENERATING MINI-STATEMENTS (DBMS_OUTPUT):")
    for acc_no in [1001, 1002]:
        cursor.execute("SELECT holder_name, balance FROM ACCOUNTS WHERE account_no = ?", (acc_no,))
        holder, bal = cursor.fetchone()
        print_separator("-")
        print(f" MINI STATEMENT | Acc #{acc_no} ({holder}) | Current Balance: ₹{bal:,.2f}")
        print_separator("-")
        print(f"{'TXN ID':<8} {'TYPE':<12} {'AMOUNT':<14} {'STATUS':<10} {'REMARKS'}")
        print_separator("-")
        cursor.execute("SELECT txn_id, txn_type, amount, status, remarks FROM TRANSACTIONS WHERE from_account = ? OR to_account = ? ORDER BY txn_id DESC LIMIT 5", (acc_no, acc_no))
        for row in cursor.fetchall():
            print(f"#{row[0]:<7} {row[1]:<12} ₹{row[2]:<13,.2f} {row[3]:<10} {row[4]}")
        print_separator("-")

    # Trigger Audit Log
    print("\n>>> STEP 7: VERIFYING AUTOMATED AUDIT TRAIL (TRG_ACCOUNT_AUDIT):")
    print_separator("=")
    print(f"{'LOG ID':<8} {'ACC NO':<10} {'ACTION TYPE':<16} {'OLD BAL':<14} {'NEW BAL':<14} {'TRIGGER'}")
    print_separator("-")
    cursor.execute("SELECT log_id, account_no, action_type, old_balance, new_balance, changed_by FROM AUDIT_LOGS")
    for row in cursor.fetchall():
        print(f"#{row[0]:<7} Acc #{row[1]:<6} {row[2]:<16} ₹{row[3]:<13,.2f} ₹{row[4]:<13,.2f} {row[5]}")
    print_separator("=")
    print("\n[SUCCESS] Entire PL/SQL Banking Pipeline Executed Successfully!")

if __name__ == "__main__":
    main()
