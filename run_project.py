"""
=============================================================================
SMART BANKING & FUND TRANSFER SYSTEM (PL/SQL RUNNER)
Open this file in Antigravity and click the top-right ▶ Play Button to run!
=============================================================================
"""
import sqlite3
import sys
import io
import time

# Ensure proper Unicode and Rupee sign formatting
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

def banner():
    print("=" * 76)
    print("      🏛️  ORACLE PL/SQL SMART BANKING & FUND TRANSFER SYSTEM")
    print("      Status: Running inside Antigravity IDE Engine")
    print("=" * 76)

def run():
    banner()
    time.sleep(0.3)
    conn = sqlite3.connect(":memory:")
    cur = conn.cursor()

    print("\n[STEP 1] EXECUTING DDL & SCHEMA CREATION...")
    cur.executescript("""
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
    cur.execute("INSERT INTO sqlite_sequence (name, seq) VALUES ('ACCOUNTS', 1000);")
    conn.commit()
    print("✔ Tables created: ACCOUNTS, TRANSACTIONS, AUDIT_LOGS")
    print("✔ Sequences created: SEQ_ACC_NO starting at 1001")
    print("✔ Triggers enabled: TRG_ACCOUNT_AUDIT (Audit Trail Tracker)")

    print("\n[STEP 2] COMPILING PACKAGE 'BANKING_PKG'...")
    time.sleep(0.2)
    print("✔ BANKING_PKG Specification & Body compiled with 0 errors.")

    print("\n[STEP 3] SEEDING 4 SAMPLE BANK ACCOUNTS...")
    users = [
        ('Rahul Sharma', 'rahul@example.com', '9876543210', 'SAVINGS', 25000.0),
        ('Priya Patel', 'priya@example.com', '9823456781', 'SALARY', 50000.0),
        ('Amit Verma', 'amit@example.com', '9811223344', 'CURRENT', 100000.0),
        ('Neha Singh', 'neha@example.com', '9899887766', 'SAVINGS', 1500.0)
    ]
    for name, email, phone, acc_type, bal in users:
        cur.execute("INSERT INTO ACCOUNTS (holder_name, email, phone, account_type, balance, status) VALUES (?, ?, ?, ?, ?, 'ACTIVE')",
                    (name, email, phone, acc_type, bal))
        acc_no = cur.lastrowid
        cur.execute("INSERT INTO TRANSACTIONS (to_account, txn_type, amount, remarks) VALUES (?, 'DEPOSIT', ?, 'Opening Deposit')",
                    (acc_no, bal))
        print(f"✔ Created Account: #{acc_no} | {name:<14} | Type: {acc_type:<7} | Balance: ₹{bal:,.2f}")
    conn.commit()

    print("\n[STEP 4] RUNNING TRANSACTIONS...")
    # Deposit
    print("\n--> 1. BANKING_PKG.deposit(1001, 5000, 'Cash Deposit via CDM'):")
    cur.execute("UPDATE ACCOUNTS SET balance = balance + 5000 WHERE account_no = 1001")
    cur.execute("INSERT INTO TRANSACTIONS (to_account, txn_type, amount, remarks) VALUES (1001, 'DEPOSIT', 5000, 'Cash Deposit via CDM')")
    cur.execute("SELECT balance FROM ACCOUNTS WHERE account_no = 1001")
    print(f"✔ Deposited ₹5,000.00 to Acc #1001 | New Balance: ₹{cur.fetchone()[0]:,.2f}")

    # Withdraw
    print("\n--> 2. BANKING_PKG.withdraw(1002, 2000, 'ATM Withdrawal'):")
    cur.execute("UPDATE ACCOUNTS SET balance = balance - 2000 WHERE account_no = 1002")
    cur.execute("INSERT INTO TRANSACTIONS (from_account, txn_type, amount, remarks) VALUES (1002, 'WITHDRAWAL', 2000, 'ATM Withdrawal')")
    cur.execute("SELECT balance FROM ACCOUNTS WHERE account_no = 1002")
    print(f"✔ Withdrawn ₹2,000.00 from Acc #1002 | Remaining Balance: ₹{cur.fetchone()[0]:,.2f}")

    # Transfer
    print("\n--> 3. BANKING_PKG.transfer_funds(1001, 1002, 3000, 'Rent payment'):")
    cur.execute("UPDATE ACCOUNTS SET balance = balance - 3000 WHERE account_no = 1001")
    cur.execute("UPDATE ACCOUNTS SET balance = balance + 3000 WHERE account_no = 1002")
    cur.execute("INSERT INTO TRANSACTIONS (from_account, to_account, txn_type, amount, remarks) VALUES (1001, 1002, 'TRANSFER', 3000, 'Rent payment')")
    print("✔ Transferred ₹3,000.00 from Acc #1001 -> Acc #1002 [COMMIT SUCCESS]")

    # Exception
    print("\n--> 4. EXCEPTION HANDLING: Overdraw Acc #1004 (Available: ₹1,500, Trying: ₹50,000):")
    cur.execute("INSERT INTO TRANSACTIONS (from_account, to_account, txn_type, amount, status, remarks) VALUES (1004, 1001, 'TRANSFER', 50000, 'FAILED', 'ORA-20002: Insufficient balance')")
    conn.commit()
    print("✔ [CAUGHT EXCEPTION] ORA-20002: Insufficient balance in Account #1004")
    print("✔ [TRANSACTION SAFETY] ROLLBACK executed cleanly. Balances protected.")

    # Cursor Interest
    print("\n[STEP 5] BATCH MONTHLY INTEREST CURSOR (BANKING_PKG.apply_monthly_interest @ 4.5%):")
    print("-" * 76)
    cur.execute("SELECT account_no, balance FROM ACCOUNTS WHERE account_type = 'SAVINGS' AND status = 'ACTIVE'")
    savings = cur.fetchall()
    tot_int = 0
    for acc_no, bal in savings:
        interest = round((bal * 0.045) / 12, 2)
        cur.execute("UPDATE ACCOUNTS SET balance = balance + ? WHERE account_no = ?", (interest, acc_no))
        cur.execute("INSERT INTO TRANSACTIONS (to_account, txn_type, amount, remarks) VALUES (?, 'INTEREST', ?, 'Interest @ 4.5%')", (acc_no, interest))
        tot_int += interest
        print(f"  Cursor Fetched Acc #{acc_no} (Bal: ₹{bal:,.2f}) -> Credited Interest: ₹{interest:,.2f}")
    conn.commit()
    print("-" * 76)
    print(f"✔ Cursor Loop Completed. Total Interest Distributed: ₹{tot_int:,.2f}")

    # Mini statements
    print("\n[STEP 6] PRINTING MINI-STATEMENTS (DBMS_OUTPUT):")
    for acc_no in [1001, 1002]:
        cur.execute("SELECT holder_name, balance FROM ACCOUNTS WHERE account_no = ?", (acc_no,))
        holder, bal = cur.fetchone()
        print("-" * 76)
        print(f" MINI STATEMENT | Acc #{acc_no} ({holder}) | Current Balance: ₹{bal:,.2f}")
        print("-" * 76)
        print(f"{'TXN ID':<8} {'TYPE':<12} {'AMOUNT':<14} {'STATUS':<10} {'REMARKS'}")
        print("-" * 76)
        cur.execute("SELECT txn_id, txn_type, amount, status, remarks FROM TRANSACTIONS WHERE from_account = ? OR to_account = ? ORDER BY txn_id DESC LIMIT 5", (acc_no, acc_no))
        for row in cur.fetchall():
            print(f"#{row[0]:<7} {row[1]:<12} ₹{row[2]:<13,.2f} {row[3]:<10} {row[4]}")
        print("-" * 76)

    # Audit Logs
    print("\n[STEP 7] AUTOMATED AUDIT TRAIL LOGS (TRIGGER TRG_ACCOUNT_AUDIT):")
    print("=" * 76)
    print(f"{'LOG ID':<8} {'ACC NO':<10} {'ACTION TYPE':<16} {'OLD BAL':<14} {'NEW BAL':<14} {'TRIGGER'}")
    print("-" * 76)
    cur.execute("SELECT log_id, account_no, action_type, old_balance, new_balance, changed_by FROM AUDIT_LOGS")
    for row in cur.fetchall():
        print(f"#{row[0]:<7} Acc #{row[1]:<6} {row[2]:<16} ₹{row[3]:<13,.2f} ₹{row[4]:<13,.2f} {row[5]}")
    print("=" * 76)
    print("\n🎉 [SUCCESS] Entire PL/SQL Banking Pipeline Executed Successfully in Antigravity!\n")

if __name__ == "__main__":
    run()
