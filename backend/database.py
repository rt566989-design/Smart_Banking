"""
ADBMS & Oracle PL/SQL Database Engine
Handles SQLite connection, schema setup, partitioned tables,
triggers, autonomous transaction fraud logs, distributed 2PC ledgers,
and materialized view tables.
"""
import sqlite3
import os

DB_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "smart_banking.db")

def get_connection():
    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row
    return conn

def init_database():
    """Initializes tables, simulated partitions, triggers, and seeds realistic multi-branch data."""
    conn = get_connection()
    cursor = conn.cursor()

    cursor.executescript("""
        DROP TABLE IF EXISTS FRAUD_ALERTS;
        DROP TABLE IF EXISTS DISTRIBUTED_TXN_LOG;
        DROP TABLE IF EXISTS AUDIT_LOGS;
        DROP TABLE IF EXISTS TRANSACTIONS_PARTITIONED;
        DROP TABLE IF EXISTS TRANSACTIONS;
        DROP TABLE IF EXISTS ACCOUNTS_PARTITIONED;
        DROP TABLE IF EXISTS ACCOUNTS;
        DROP TABLE IF EXISTS CUSTOMERS_OBJ;
        DROP TABLE IF EXISTS BRANCHES;
        DROP TABLE IF EXISTS MV_DAILY_BRANCH_SUMMARY;
        DROP TABLE IF EXISTS MV_CUSTOMER_NETWORTH;

        -- 1. BRANCHES (Distributed Multi-Region Network)
        CREATE TABLE BRANCHES (
            branch_code      TEXT PRIMARY KEY,
            branch_name      TEXT NOT NULL,
            city             TEXT NOT NULL,
            region           TEXT NOT NULL CHECK (region IN ('NORTH', 'SOUTH', 'EAST', 'WEST')),
            ifsc_code        TEXT UNIQUE NOT NULL,
            created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        -- 2. CUSTOMERS_OBJ (ORDBMS Simulation: User Types, KYC, Phone Array)
        CREATE TABLE CUSTOMERS_OBJ (
            customer_id      INTEGER PRIMARY KEY,
            full_name        TEXT NOT NULL,
            email            TEXT UNIQUE NOT NULL,
            phone_list       TEXT, -- JSON/CSV array: ["9876543210", "0112345678"]
            street_address   TEXT,
            city             TEXT,
            state            TEXT,
            pincode          TEXT,
            kyc_type         TEXT,
            kyc_number       TEXT,
            kyc_status       TEXT DEFAULT 'VERIFIED',
            created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        -- 3. ACCOUNTS (Core Account Ledger)
        CREATE TABLE ACCOUNTS (
            account_no       INTEGER PRIMARY KEY AUTOINCREMENT,
            customer_id      INTEGER,
            branch_code      TEXT,
            holder_name      TEXT NOT NULL,
            email            TEXT UNIQUE NOT NULL,
            phone            TEXT NOT NULL,
            account_type     TEXT DEFAULT 'SAVINGS' CHECK (account_type IN ('SAVINGS', 'CURRENT', 'SALARY')),
            balance          REAL DEFAULT 0.0 CHECK (balance >= 0),
            daily_limit      REAL DEFAULT 50000.0,
            status           TEXT DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'DORMANT', 'FROZEN', 'CLOSED')),
            created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY(branch_code) REFERENCES BRANCHES(branch_code)
        );

        -- 4. ACCOUNTS_PARTITIONED (ADBMS List Partitioning by account_type)
        CREATE TABLE ACCOUNTS_PARTITIONED (
            account_no       INTEGER,
            holder_name      TEXT NOT NULL,
            branch_code      TEXT NOT NULL,
            account_type     TEXT NOT NULL,
            balance          REAL NOT NULL,
            partition_name   TEXT NOT NULL, -- 'P_SAVINGS', 'P_CURRENT', 'P_SALARY'
            status           TEXT DEFAULT 'ACTIVE',
            PRIMARY KEY(account_no, account_type)
        );

        -- 5. TRANSACTIONS (Base ledger)
        CREATE TABLE TRANSACTIONS (
            txn_id           INTEGER PRIMARY KEY AUTOINCREMENT,
            from_account     INTEGER,
            to_account       INTEGER,
            txn_type         TEXT NOT NULL CHECK (txn_type IN ('DEPOSIT', 'WITHDRAWAL', 'TRANSFER', 'INTEREST', 'FEE')),
            amount           REAL NOT NULL CHECK (amount > 0),
            txn_date         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            status           TEXT DEFAULT 'SUCCESS' CHECK (status IN ('SUCCESS', 'FAILED')),
            remarks          TEXT,
            FOREIGN KEY(from_account) REFERENCES ACCOUNTS(account_no),
            FOREIGN KEY(to_account) REFERENCES ACCOUNTS(account_no)
        );

        -- 6. TRANSACTIONS_PARTITIONED (ADBMS Range Partitioning by txn_date)
        CREATE TABLE TRANSACTIONS_PARTITIONED (
            txn_id           INTEGER,
            from_account     INTEGER,
            to_account       INTEGER,
            txn_type         TEXT NOT NULL,
            amount           REAL NOT NULL,
            txn_date         TEXT NOT NULL,
            partition_name   TEXT NOT NULL, -- 'P_2025_Q1', 'P_2025_Q2', 'P_2025_Q3', 'P_2025_Q4', 'P_2026_Q1', 'P_FUTURE'
            status           TEXT DEFAULT 'SUCCESS',
            remarks          TEXT,
            PRIMARY KEY(txn_id, txn_date)
        );

        -- 7. AUDIT_LOGS TABLE (Trigger target)
        CREATE TABLE AUDIT_LOGS (
            log_id           INTEGER PRIMARY KEY AUTOINCREMENT,
            account_no       INTEGER NOT NULL,
            action_type      TEXT NOT NULL,
            old_balance      REAL,
            new_balance      REAL,
            changed_by       TEXT DEFAULT 'TRG_ACCOUNT_AUDIT',
            changed_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        -- 8. FRAUD_ALERTS (Autonomous Transaction Target)
        CREATE TABLE FRAUD_ALERTS (
            alert_id         INTEGER PRIMARY KEY AUTOINCREMENT,
            account_no       INTEGER,
            severity         TEXT CHECK (severity IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
            reason           TEXT NOT NULL,
            attempted_amount REAL,
            ip_address       TEXT DEFAULT '127.0.0.1',
            alert_time       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            resolved         TEXT DEFAULT 'NO'
        );

        -- 9. DISTRIBUTED_TXN_LOG (2-Phase Commit Coordinator Ledger)
        CREATE TABLE DISTRIBUTED_TXN_LOG (
            dtxn_id          INTEGER PRIMARY KEY AUTOINCREMENT,
            global_xid       TEXT NOT NULL,
            source_branch    TEXT,
            target_branch    TEXT,
            from_account     INTEGER,
            to_account       INTEGER,
            amount           REAL NOT NULL,
            phase_1_status   TEXT DEFAULT 'PREPARED',
            phase_2_status   TEXT DEFAULT 'COMMITTED',
            created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        -- 10. MATERIALIZED VIEW SIMULATION TABLES (OLAP Aggregations)
        CREATE TABLE MV_DAILY_BRANCH_SUMMARY (
            branch_code             TEXT PRIMARY KEY,
            branch_name             TEXT NOT NULL,
            region                  TEXT NOT NULL,
            total_accounts          INTEGER,
            total_branch_liquidity  REAL,
            avg_account_balance     REAL,
            last_refreshed          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE MV_CUSTOMER_NETWORTH (
            holder_name      TEXT PRIMARY KEY,
            email            TEXT,
            num_accounts     INTEGER,
            total_networth   REAL,
            client_tier      TEXT,
            last_refreshed   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        -- DML TRIGGER: Automated Balance & Audit Trail Tracker
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

    # Seed starting sequences
    cursor.execute("INSERT INTO sqlite_sequence (name, seq) VALUES ('ACCOUNTS', 1000);")
    cursor.execute("INSERT INTO sqlite_sequence (name, seq) VALUES ('TRANSACTIONS', 50000);")
    cursor.execute("INSERT INTO sqlite_sequence (name, seq) VALUES ('FRAUD_ALERTS', 80000);")
    cursor.execute("INSERT INTO sqlite_sequence (name, seq) VALUES ('DISTRIBUTED_TXN_LOG', 90000);")

    # 1. Seed Branches
    branches = [
        ('BR-DEL-01', 'Connaught Place Branch', 'New Delhi', 'NORTH', 'SMART0001001'),
        ('BR-MUM-01', 'Nariman Point Branch', 'Mumbai', 'WEST', 'SMART0002001'),
        ('BR-BLR-01', 'Indiranagar Tech Hub', 'Bengaluru', 'SOUTH', 'SMART0003001'),
        ('BR-KOL-01', 'Park Street Branch', 'Kolkata', 'EAST', 'SMART0004001')
    ]
    cursor.executemany("INSERT INTO BRANCHES VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)", branches)

    # 2. Seed ORDBMS Customers
    customers = [
        (1001, 'Rahul Sharma', 'rahul.sharma@example.com', '["9876543210", "0112345678"]', '12/A Barakhamba Road', 'New Delhi', 'Delhi', '110001', 'AADHAAR', '4589-1234-9012'),
        (1002, 'Priya Patel', 'priya.patel@example.com', '["9823456781"]', '84 Marine Drive', 'Mumbai', 'Maharashtra', '400020', 'PAN', 'ABCDE1234F'),
        (1003, 'Amit Verma', 'amit.verma@example.com', '["9811223344"]', '100 Feet Road, Indiranagar', 'Bengaluru', 'Karnataka', '560038', 'PASSPORT', 'Z9876543'),
        (1004, 'Neha Singh', 'neha.singh@example.com', '["9899887766"]', '45 Civil Lines', 'New Delhi', 'Delhi', '110054', 'AADHAAR', '8899-7711-2233'),
        (1005, 'Vikram Malhotra', 'vikram.m@example.com', '["9833445566"]', '17 Park Street', 'Kolkata', 'West Bengal', '700016', 'PAN', 'XYZPM9988K'),
        (1006, 'Ananya Iyer', 'ananya.iyer@example.com', '["9845012345"]', '22 Koramangala 4th Block', 'Bengaluru', 'Karnataka', '560034', 'AADHAAR', '3344-5566-7788')
    ]
    cursor.executemany("""
        INSERT INTO CUSTOMERS_OBJ (customer_id, full_name, email, phone_list, street_address, city, state, pincode, kyc_type, kyc_number)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, customers)

    # 3. Seed Accounts
    accounts = [
        (1001, 1001, 'BR-DEL-01', 'Rahul Sharma', 'rahul.sharma@example.com', '+91 98765 43210', 'SAVINGS', 75000.0, 50000.0),
        (1002, 1002, 'BR-MUM-01', 'Priya Patel', 'priya.patel@example.com', '+91 98234 56781', 'SALARY', 120000.0, 75000.0),
        (1003, 1003, 'BR-BLR-01', 'Amit Verma', 'amit.verma@example.com', '+91 98112 23344', 'CURRENT', 250000.0, 150000.0),
        (1004, 1004, 'BR-DEL-01', 'Neha Singh', 'neha.singh@example.com', '+91 98998 87766', 'SAVINGS', 15000.0, 50000.0),
        (1005, 1005, 'BR-KOL-01', 'Vikram Malhotra', 'vikram.m@example.com', '+91 98334 45566', 'CURRENT', 680000.0, 200000.0),
        (1006, 1006, 'BR-BLR-01', 'Ananya Iyer', 'ananya.iyer@example.com', '+91 98450 12345', 'SAVINGS', 850.0, 25000.0)
    ]
    cursor.executemany("""
        INSERT INTO ACCOUNTS (account_no, customer_id, branch_code, holder_name, email, phone, account_type, balance, daily_limit, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'ACTIVE')
    """, accounts)

    # 4. Sync into List-Partitioned Accounts table
    cursor.execute("""
        INSERT INTO ACCOUNTS_PARTITIONED (account_no, holder_name, branch_code, account_type, balance, partition_name, status)
        SELECT account_no, holder_name, branch_code, account_type, balance, 'P_' || account_type, status FROM ACCOUNTS;
    """)

    # 5. Seed Historical Multi-Quarter Transactions into TRANSACTIONS and Range-Partitioned Table
    txns = [
        (50001, None, 1001, 'DEPOSIT', 50000.0, '2025-01-15 10:30:00', 'P_2025_Q1', 'SUCCESS', 'Opening Deposit'),
        (50002, 1001, 1004, 'TRANSFER', 10000.0, '2025-05-10 14:15:00', 'P_2025_Q2', 'SUCCESS', 'Family Allowance'),
        (50003, None, 1002, 'DEPOSIT', 120000.0, '2025-08-01 09:00:00', 'P_2025_Q3', 'SUCCESS', 'Corporate Salary Credit'),
        (50004, 1003, 1005, 'TRANSFER', 45000.0, '2025-11-20 16:45:00', 'P_2025_Q4', 'SUCCESS', 'B2B Vendor Settlement'),
        (50005, None, 1001, 'DEPOSIT', 35000.0, '2026-02-14 11:20:00', 'P_2026_Q1', 'SUCCESS', 'UPI Inward Credit')
    ]
    for tid, s_acc, d_acc, ttype, amt, tdate, part, stat, rem in txns:
        cursor.execute("""
            INSERT INTO TRANSACTIONS (txn_id, from_account, to_account, txn_type, amount, txn_date, status, remarks)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (tid, s_acc, d_acc, ttype, amt, tdate, stat, rem))

        cursor.execute("""
            INSERT INTO TRANSACTIONS_PARTITIONED (txn_id, from_account, to_account, txn_type, amount, txn_date, partition_name, status, remarks)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (tid, s_acc, d_acc, ttype, amt, tdate[:10], part, stat, rem))

    # 6. Seed Sample Autonomous Fraud Alerts
    fraud_seed = [
        (80001, 1004, 'HIGH', 'Daily transaction limit of ₹50,000.00 breached! Attempted: ₹60,000.00', 60000.0, '192.168.1.105', 'NO'),
        (80002, 1006, 'MEDIUM', 'Overdraft attempt: balance ₹850.00, tried ₹10,000.00', 10000.0, '192.168.1.108', 'YES')
    ]
    cursor.executemany("""
        INSERT INTO FRAUD_ALERTS (alert_id, account_no, severity, reason, attempted_amount, ip_address, resolved)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    """, fraud_seed)

    # 7. Seed Sample 2PC Distributed Transactions
    dtxn_seed = [
        (90001, 'GTXN-20251120-164500-0012', 'BR-DEL-01', 'BR-BLR-01', 1001, 1003, 15000.0, 'VOTE_COMMIT', 'GLOBAL_COMMITTED')
    ]
    cursor.executemany("""
        INSERT INTO DISTRIBUTED_TXN_LOG (dtxn_id, global_xid, source_branch, target_branch, from_account, to_account, amount, phase_1_status, phase_2_status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, dtxn_seed)

    # 8. Refresh Materialized Views
    _refresh_mviews(cursor)

    conn.commit()
    conn.close()

def _refresh_mviews(cursor):
    """Refreshes simulated materialized view tables."""
    cursor.execute("DELETE FROM MV_DAILY_BRANCH_SUMMARY")
    cursor.execute("""
        INSERT INTO MV_DAILY_BRANCH_SUMMARY (branch_code, branch_name, region, total_accounts, total_branch_liquidity, avg_account_balance, last_refreshed)
        SELECT 
            b.branch_code,
            b.branch_name,
            b.region,
            COUNT(a.account_no) AS total_accounts,
            COALESCE(SUM(a.balance), 0) AS total_branch_liquidity,
            ROUND(COALESCE(AVG(a.balance), 0), 2) AS avg_account_balance,
            CURRENT_TIMESTAMP
        FROM BRANCHES b
        LEFT JOIN ACCOUNTS a ON b.branch_code = a.branch_code AND a.status = 'ACTIVE'
        GROUP BY b.branch_code, b.branch_name, b.region
    """)

    cursor.execute("DELETE FROM MV_CUSTOMER_NETWORTH")
    cursor.execute("""
        INSERT INTO MV_CUSTOMER_NETWORTH (holder_name, email, num_accounts, total_networth, client_tier, last_refreshed)
        SELECT 
            holder_name,
            email,
            COUNT(account_no) AS num_accounts,
            SUM(balance) AS total_networth,
            CASE 
                WHEN SUM(balance) >= 500000 THEN 'HIGH NET WORTH (HNW)'
                WHEN SUM(balance) >= 100000 THEN 'PREMIUM RETAIL'
                ELSE 'STANDARD RETAIL'
            END AS client_tier,
            CURRENT_TIMESTAMP
        FROM ACCOUNTS
        GROUP BY holder_name, email
    """)
