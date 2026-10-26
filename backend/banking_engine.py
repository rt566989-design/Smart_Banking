"""
ADBMS Banking Business Engine (Oracle PL/SQL & ADBMS Core)
Implements all ADBMS concepts:
  - ACID Core Operations with Row Locks
  - Autonomous Transactions (Independent Fraud Log on Rollback)
  - Compound Trigger Daily Cap Sentinel (Mutating Table Error Bypass)
  - High-Performance Bulk Processing (BULK COLLECT & FORALL Simulation)
  - Materialized Views & Fast Refresh
  - Range & List Partitioning Data Access
  - Distributed 2-Phase Commit (2PC) Protocol
  - OLAP Analytical Window Computations
"""
import time
import json
from datetime import datetime
from backend.database import get_connection, _refresh_mviews

class BankingEngine:

    # =========================================================================
    # CORE METRICS & ACCOUNTS
    # =========================================================================
    @staticmethod
    def get_all_accounts():
        conn = get_connection()
        accounts = conn.execute("""
            SELECT a.*, b.branch_name, b.region 
            FROM ACCOUNTS a
            LEFT JOIN BRANCHES b ON a.branch_code = b.branch_code
            ORDER BY a.account_no ASC
        """).fetchall()
        conn.close()
        return [dict(a) for a in accounts]

    @staticmethod
    def get_account_by_id(account_no):
        conn = get_connection()
        acc = conn.execute("""
            SELECT a.*, b.branch_name, b.region 
            FROM ACCOUNTS a
            LEFT JOIN BRANCHES b ON a.branch_code = b.branch_code
            WHERE a.account_no = ?
        """, (account_no,)).fetchone()
        conn.close()
        return dict(acc) if acc else None

    # =========================================================================
    # ORDBMS CUSTOMER ONBOARDING
    # =========================================================================
    @staticmethod
    def open_account_ordbms(name, email, phones, address, kyc, branch_code="BR-DEL-01", acc_type="SAVINGS", initial_deposit=0.0):
        if initial_deposit < 0:
            raise ValueError("ORA-20004: Initial deposit cannot be negative.")

        conn = get_connection()
        cur = conn.cursor()
        try:
            cur.execute("""
                INSERT INTO CUSTOMERS_OBJ (full_name, email, phone_list, street_address, city, state, pincode, kyc_type, kyc_number)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                name.strip(),
                email.strip().lower(),
                json.dumps(phones if isinstance(phones, list) else [phones]),
                address.get("street", "12 Main St"),
                address.get("city", "New Delhi"),
                address.get("state", "Delhi"),
                address.get("pincode", "110001"),
                kyc.get("doc_type", "AADHAAR"),
                kyc.get("doc_number", "4589-1234-9012")
            ))
            cust_id = cur.lastrowid
            phone_primary = phones[0] if isinstance(phones, list) and phones else str(phones)

            cur.execute("""
                INSERT INTO ACCOUNTS (customer_id, branch_code, holder_name, email, phone, account_type, balance, daily_limit, status)
                VALUES (?, ?, ?, ?, ?, ?, ?, 50000.0, 'ACTIVE')
            """, (cust_id, branch_code, name.strip(), email.strip().lower(), phone_primary, acc_type.upper(), initial_deposit))
            acc_no = cur.lastrowid

            # Sync List Partition
            cur.execute("""
                INSERT INTO ACCOUNTS_PARTITIONED (account_no, holder_name, branch_code, account_type, balance, partition_name, status)
                VALUES (?, ?, ?, ?, ?, ?, 'ACTIVE')
            """, (acc_no, name.strip(), branch_code, acc_type.upper(), initial_deposit, f"P_{acc_type.upper()}"))

            # Opening Deposit Txn
            if initial_deposit > 0:
                cur.execute("""
                    INSERT INTO TRANSACTIONS (to_account, txn_type, amount, status, remarks)
                    VALUES (?, 'DEPOSIT', ?, 'SUCCESS', 'Opening Deposit')
                """, (acc_no, initial_deposit))
                txn_id = cur.lastrowid

                cur.execute("""
                    INSERT INTO TRANSACTIONS_PARTITIONED (txn_id, to_account, txn_type, amount, txn_date, partition_name, status, remarks)
                    VALUES (?, ?, 'DEPOSIT', ?, date('now'), 'P_2026_Q1', 'SUCCESS', 'Opening Deposit')
                """, (txn_id, acc_no, initial_deposit))

            _refresh_mviews(cur)
            conn.commit()
            return {"account_no": acc_no, "holder_name": name, "balance": initial_deposit}
        except Exception as e:
            conn.rollback()
            BankingEngine.log_fraud_alert_autonomous(0, "MEDIUM", f"Account onboarding error: {str(e)}", initial_deposit)
            raise e
        finally:
            conn.close()

    # =========================================================================
    # AUTONOMOUS TRANSACTIONS (PRAGMA AUTONOMOUS_TRANSACTION SIMULATION)
    # =========================================================================
    @staticmethod
    def log_fraud_alert_autonomous(account_no, severity, reason, attempted_amount, ip_address="192.168.1.105"):
        """Logs security / fraud events in an independent transaction that commits immediately."""
        conn = get_connection()
        try:
            cur = conn.cursor()
            cur.execute("""
                INSERT INTO FRAUD_ALERTS (account_no, severity, reason, attempted_amount, ip_address, alert_time, resolved)
                VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP, 'NO')
            """, (account_no, severity.upper(), reason, attempted_amount, ip_address))
            conn.commit()
        except Exception as e:
            print(f"[AUTONOMOUS ERROR] Failed to log alert: {e}")
        finally:
            conn.close()

    # =========================================================================
    # ATOMIC OPERATIONS WITH COMPOUND TRIGGER DAILY LIMIT CHECK
    # =========================================================================
    @staticmethod
    def deposit(account_no, amount, remarks="Cash Deposit"):
        if amount <= 0:
            raise ValueError("ORA-20004: Deposit amount must be strictly greater than zero.")

        conn = get_connection()
        cur = conn.cursor()
        try:
            acc = cur.execute("SELECT balance, status FROM ACCOUNTS WHERE account_no = ?", (account_no,)).fetchone()
            if not acc:
                raise ValueError(f"ORA-20006: Account #{account_no} does not exist.")
            if acc["status"] != 'ACTIVE':
                raise ValueError(f"ORA-20003: Account #{account_no} is {acc['status']}.")

            new_bal = acc["balance"] + amount
            cur.execute("UPDATE ACCOUNTS SET balance = ? WHERE account_no = ?", (new_bal, account_no))
            cur.execute("UPDATE ACCOUNTS_PARTITIONED SET balance = ? WHERE account_no = ?", (new_bal, account_no))

            cur.execute("""
                INSERT INTO TRANSACTIONS (to_account, txn_type, amount, status, remarks)
                VALUES (?, 'DEPOSIT', ?, 'SUCCESS', ?)
            """, (account_no, amount, remarks))
            txn_id = cur.lastrowid

            cur.execute("""
                INSERT INTO TRANSACTIONS_PARTITIONED (txn_id, to_account, txn_type, amount, txn_date, partition_name, status, remarks)
                VALUES (?, ?, 'DEPOSIT', ?, date('now'), 'P_2026_Q1', 'SUCCESS', ?)
            """, (txn_id, account_no, amount, remarks))

            _refresh_mviews(cur)
            conn.commit()
            return {"account_no": account_no, "deposited": amount, "new_balance": new_bal}
        except Exception as e:
            conn.rollback()
            raise e
        finally:
            conn.close()

    @staticmethod
    def withdraw(account_no, amount, remarks="Cash Withdrawal"):
        if amount <= 0:
            raise ValueError("ORA-20004: Withdrawal amount must be greater than zero.")

        conn = get_connection()
        cur = conn.cursor()
        try:
            acc = cur.execute("SELECT balance, status, daily_limit FROM ACCOUNTS WHERE account_no = ?", (account_no,)).fetchone()
            if not acc:
                raise ValueError(f"ORA-20006: Account #{account_no} does not exist.")
            if acc["status"] != 'ACTIVE':
                raise ValueError(f"ORA-20003: Account #{account_no} is {acc['status']}.")

            # Compound Trigger: Enforce daily limit
            today_spent = cur.execute("""
                SELECT COALESCE(SUM(amount), 0) FROM TRANSACTIONS 
                WHERE from_account = ? AND txn_type IN ('WITHDRAWAL', 'TRANSFER') AND status = 'SUCCESS'
                  AND date(txn_date) = date('now')
            """, (account_no,)).fetchone()[0]

            if (today_spent + amount) > acc["daily_limit"]:
                BankingEngine.log_fraud_alert_autonomous(
                    account_no, 'HIGH',
                    f"Daily transaction limit ₹{acc['daily_limit']:,.2f} breached! Today attempted: ₹{today_spent + amount:,.2f}",
                    amount
                )
                raise ValueError(f"ORA-20010: Daily Transaction Limit Exceeded! Daily limit is ₹{acc['daily_limit']:,.2f}. Attempted total: ₹{today_spent + amount:,.2f}")

            # Balance check
            if acc["balance"] < amount:
                BankingEngine.log_fraud_alert_autonomous(
                    account_no, 'MEDIUM',
                    f"Overdraft attempt: balance ₹{acc['balance']:,.2f}, tried ₹{amount:,.2f}",
                    amount
                )
                raise ValueError(f"ORA-20002: Insufficient funds. Available: ₹{acc['balance']:,.2f}, Requested: ₹{amount:,.2f}")

            new_bal = acc["balance"] - amount
            cur.execute("UPDATE ACCOUNTS SET balance = ? WHERE account_no = ?", (new_bal, account_no))
            cur.execute("UPDATE ACCOUNTS_PARTITIONED SET balance = ? WHERE account_no = ?", (new_bal, account_no))

            cur.execute("""
                INSERT INTO TRANSACTIONS (from_account, txn_type, amount, status, remarks)
                VALUES (?, 'WITHDRAWAL', ?, 'SUCCESS', ?)
            """, (account_no, amount, remarks))
            txn_id = cur.lastrowid

            cur.execute("""
                INSERT INTO TRANSACTIONS_PARTITIONED (txn_id, from_account, txn_type, amount, txn_date, partition_name, status, remarks)
                VALUES (?, ?, 'WITHDRAWAL', ?, date('now'), 'P_2026_Q1', 'SUCCESS', ?)
            """, (txn_id, account_no, amount, remarks))

            _refresh_mviews(cur)
            conn.commit()
            return {"account_no": account_no, "withdrawn": amount, "remaining_balance": new_bal}
        except Exception as e:
            conn.rollback()
            raise e
        finally:
            conn.close()

    @staticmethod
    def transfer_funds(from_acc, to_acc, amount, remarks="Fund Transfer"):
        if from_acc == to_acc:
            raise ValueError("ORA-20005: Sender and Receiver account numbers cannot be identical.")
        if amount <= 0:
            raise ValueError("ORA-20004: Transfer amount must be greater than zero.")

        conn = get_connection()
        cur = conn.cursor()
        try:
            s_acc = cur.execute("SELECT balance, status, daily_limit FROM ACCOUNTS WHERE account_no = ?", (from_acc,)).fetchone()
            r_acc = cur.execute("SELECT balance, status FROM ACCOUNTS WHERE account_no = ?", (to_acc,)).fetchone()

            if not s_acc:
                raise ValueError(f"ORA-20006: Sender Account #{from_acc} not found.")
            if not r_acc:
                raise ValueError(f"ORA-20006: Receiver Account #{to_acc} not found.")

            if s_acc["status"] != 'ACTIVE':
                raise ValueError(f"ORA-20003: Sender Account #{from_acc} is {s_acc['status']}.")
            if r_acc["status"] != 'ACTIVE':
                raise ValueError(f"ORA-20003: Receiver Account #{to_acc} is {r_acc['status']}.")

            # Compound Trigger Daily Limit Cap
            today_spent = cur.execute("""
                SELECT COALESCE(SUM(amount), 0) FROM TRANSACTIONS 
                WHERE from_account = ? AND txn_type IN ('WITHDRAWAL', 'TRANSFER') AND status = 'SUCCESS'
                  AND date(txn_date) = date('now')
            """, (from_acc,)).fetchone()[0]

            if (today_spent + amount) > s_acc["daily_limit"]:
                BankingEngine.log_fraud_alert_autonomous(
                    from_acc, 'HIGH',
                    f"Daily transaction limit ₹{s_acc['daily_limit']:,.2f} breached! Today attempted: ₹{today_spent + amount:,.2f}",
                    amount
                )
                raise ValueError(f"ORA-20010: Daily Transaction Limit Exceeded! Daily limit is ₹{s_acc['daily_limit']:,.2f}. Attempted total: ₹{today_spent + amount:,.2f}")

            if s_acc["balance"] < amount:
                BankingEngine.log_fraud_alert_autonomous(
                    from_acc, 'MEDIUM',
                    f"Transfer aborted: Insufficient balance ₹{s_acc['balance']:,.2f}, required ₹{amount:,.2f}",
                    amount
                )
                raise ValueError(f"ORA-20002: Insufficient funds in Acc #{from_acc}. Available: ₹{s_acc['balance']:,.2f}")

            # Atomic Transfer
            cur.execute("UPDATE ACCOUNTS SET balance = balance - ? WHERE account_no = ?", (amount, from_acc))
            cur.execute("UPDATE ACCOUNTS SET balance = balance + ? WHERE account_no = ?", (amount, to_acc))

            cur.execute("UPDATE ACCOUNTS_PARTITIONED SET balance = balance - ? WHERE account_no = ?", (amount, from_acc))
            cur.execute("UPDATE ACCOUNTS_PARTITIONED SET balance = balance + ? WHERE account_no = ?", (amount, to_acc))

            cur.execute("""
                INSERT INTO TRANSACTIONS (from_account, to_account, txn_type, amount, status, remarks)
                VALUES (?, ?, 'TRANSFER', ?, 'SUCCESS', ?)
            """, (from_acc, to_acc, amount, remarks))
            txn_id = cur.lastrowid

            cur.execute("""
                INSERT INTO TRANSACTIONS_PARTITIONED (txn_id, from_account, to_account, txn_type, amount, txn_date, partition_name, status, remarks)
                VALUES (?, ?, ?, 'TRANSFER', ?, date('now'), 'P_2026_Q1', 'SUCCESS', ?)
            """, (txn_id, from_acc, to_acc, amount, remarks))

            _refresh_mviews(cur)
            conn.commit()
            return {"from_account": from_acc, "to_account": to_acc, "amount": amount, "status": "SUCCESS"}
        except Exception as e:
            conn.rollback()
            raise e
        finally:
            conn.close()

    # =========================================================================
    # HIGH-PERFORMANCE BULK OPERATIONS (BULK COLLECT & FORALL)
    # =========================================================================
    @staticmethod
    def bulk_apply_monthly_interest(annual_rate=4.5, batch_size=500):
        """Simulates Oracle BULK COLLECT & FORALL high-throughput batch interest payment."""
        start_time = time.time()
        conn = get_connection()
        cur = conn.cursor()
        try:
            savings = cur.execute("""
                SELECT account_no, balance FROM ACCOUNTS 
                WHERE account_type = 'SAVINGS' AND status = 'ACTIVE' AND balance > 0
            """).fetchall()

            total_paid = 0
            count = 0
            batch_updates = []
            batch_txns = []

            monthly_rate = (annual_rate / 100.0) / 12.0

            for row in savings:
                acc_no = row["account_no"]
                bal = row["balance"]
                interest = round(bal * monthly_rate, 2)
                if interest > 0:
                    batch_updates.append((interest, acc_no))
                    batch_txns.append((acc_no, interest, f"Bulk Interest Credit @ {annual_rate}% P.A."))
                    total_paid += interest
                    count += 1

            # High-speed bulk execution (FORALL simulation)
            cur.executemany("UPDATE ACCOUNTS SET balance = balance + ? WHERE account_no = ?", batch_updates)
            cur.executemany("UPDATE ACCOUNTS_PARTITIONED SET balance = balance + ? WHERE account_no = ?", batch_updates)
            cur.executemany("""
                INSERT INTO TRANSACTIONS (to_account, txn_type, amount, status, remarks)
                VALUES (?, 'INTEREST', ?, 'SUCCESS', ?)
            """, batch_txns)

            _refresh_mviews(cur)
            conn.commit()
            elapsed_ms = round((time.time() - start_time) * 1000, 2)
            return {
                "accounts_credited": count,
                "total_interest_paid": total_paid,
                "execution_mode": "BULK COLLECT & FORALL",
                "elapsed_ms": elapsed_ms
            }
        except Exception as e:
            conn.rollback()
            raise e
        finally:
            conn.close()

    @staticmethod
    def bulk_deduct_service_fee(fee_amount=150.0, min_tier=2000.0):
        start_time = time.time()
        conn = get_connection()
        cur = conn.cursor()
        try:
            low_bal = cur.execute("""
                SELECT account_no, balance FROM ACCOUNTS
                WHERE balance < ? AND status = 'ACTIVE' AND balance >= ?
            """, (min_tier, fee_amount)).fetchall()

            batch_updates = [(fee_amount, r["account_no"]) for r in low_bal]
            batch_txns = [(r["account_no"], fee_amount, "Low Balance Service Maintenance Fee") for r in low_bal]

            cur.executemany("UPDATE ACCOUNTS SET balance = balance - ? WHERE account_no = ?", batch_updates)
            cur.executemany("UPDATE ACCOUNTS_PARTITIONED SET balance = balance - ? WHERE account_no = ?", batch_updates)
            cur.executemany("""
                INSERT INTO TRANSACTIONS (from_account, txn_type, amount, status, remarks)
                VALUES (?, 'FEE', ?, 'SUCCESS', ?)
            """, batch_txns)

            _refresh_mviews(cur)
            conn.commit()
            elapsed_ms = round((time.time() - start_time) * 1000, 2)
            return {
                "accounts_charged": len(low_bal),
                "total_fees_collected": len(low_bal) * fee_amount,
                "elapsed_ms": elapsed_ms
            }
        except Exception as e:
            conn.rollback()
            raise e
        finally:
            conn.close()

    # =========================================================================
    # DISTRIBUTED TWO-PHASE COMMIT (2PC) SIMULATOR
    # =========================================================================
    @staticmethod
    def simulate_distributed_transfer(source_branch, target_branch, from_acc, to_acc, amount, simulate_fail="NONE"):
        gxid = f"GTXN-{datetime.now().strftime('%Y%m%d-%H%M%S')}-{int(time.time() * 1000) % 1000:03d}"
        conn = get_connection()
        cur = conn.cursor()
        try:
            if simulate_fail == "PREPARE_FAIL":
                cur.execute("""
                    INSERT INTO DISTRIBUTED_TXN_LOG (global_xid, source_branch, target_branch, from_account, to_account, amount, phase_1_status, phase_2_status)
                    VALUES (?, ?, ?, ?, ?, ?, 'VOTE_ABORT', 'GLOBAL_ROLLED_BACK')
                """, (gxid, source_branch, target_branch, from_acc, to_acc, amount))
                conn.commit()

                BankingEngine.log_fraud_alert_autonomous(
                    from_acc, 'CRITICAL',
                    f"Distributed 2PC Protocol: Target Branch {target_branch} voted ABORT during Phase 1.",
                    amount
                )
                raise ValueError(f"ORA-20015: Distributed 2PC Phase 1 Failed: Branch {target_branch} unreachable. Global Transaction Aborted.")

            # Phase 1: Prepare
            cur.execute("""
                INSERT INTO DISTRIBUTED_TXN_LOG (global_xid, source_branch, target_branch, from_account, to_account, amount, phase_1_status, phase_2_status)
                VALUES (?, ?, ?, ?, ?, ?, 'VOTE_COMMIT', 'PREPARED')
            """, (gxid, source_branch, target_branch, from_acc, to_acc, amount))
            dtxn_id = cur.lastrowid
            conn.commit()

            # Phase 2: Global Commit
            BankingEngine.transfer_funds(from_acc, to_acc, amount, f"Distributed 2PC: {gxid}")

            cur.execute("UPDATE DISTRIBUTED_TXN_LOG SET phase_2_status = 'GLOBAL_COMMITTED' WHERE dtxn_id = ?", (dtxn_id,))
            conn.commit()
            return {"global_xid": gxid, "status": "GLOBAL_COMMITTED", "source_branch": source_branch, "target_branch": target_branch}
        except Exception as e:
            conn.rollback()
            raise e
        finally:
            conn.close()

    # =========================================================================
    # PARTITIONING & MATERIALIZED VIEW ACCESS
    # =========================================================================
    @staticmethod
    def get_partitioned_transactions(partition=None):
        conn = get_connection()
        if partition and partition != 'ALL':
            txns = conn.execute("SELECT * FROM TRANSACTIONS_PARTITIONED WHERE partition_name = ? ORDER BY txn_id DESC", (partition,)).fetchall()
        else:
            txns = conn.execute("SELECT * FROM TRANSACTIONS_PARTITIONED ORDER BY txn_id DESC").fetchall()
        conn.close()
        return [dict(t) for t in txns]

    @staticmethod
    def get_partitioned_accounts(partition=None):
        conn = get_connection()
        if partition and partition != 'ALL':
            accs = conn.execute("SELECT * FROM ACCOUNTS_PARTITIONED WHERE partition_name = ? ORDER BY account_no ASC", (partition,)).fetchall()
        else:
            accs = conn.execute("SELECT * FROM ACCOUNTS_PARTITIONED ORDER BY account_no ASC").fetchall()
        conn.close()
        return [dict(a) for a in accs]

    @staticmethod
    def get_branch_summary_mview():
        conn = get_connection()
        rows = conn.execute("SELECT * FROM MV_DAILY_BRANCH_SUMMARY ORDER BY total_branch_liquidity DESC").fetchall()
        conn.close()
        return [dict(r) for r in rows]

    @staticmethod
    def get_customer_networth_mview():
        conn = get_connection()
        rows = conn.execute("SELECT * FROM MV_CUSTOMER_NETWORTH ORDER BY total_networth DESC").fetchall()
        conn.close()
        return [dict(r) for r in rows]

    @staticmethod
    def refresh_all_mviews():
        conn = get_connection()
        cur = conn.cursor()
        _refresh_mviews(cur)
        conn.commit()
        conn.close()
        return {"refreshed": True, "message": "All Materialized Views refreshed successfully."}

    # =========================================================================
    # OLAP ANALYTICS (WINDOW FUNCTIONS: RANK, RUNNING BALANCE, VELOCITY)
    # =========================================================================
    @staticmethod
    def get_olap_analytics():
        conn = get_connection()
        # Wealth ranking by region
        wealth_ranks = conn.execute("""
            SELECT 
                b.region,
                b.branch_name,
                a.account_no,
                a.holder_name,
                a.account_type,
                a.balance,
                DENSE_RANK() OVER (PARTITION BY b.region ORDER BY a.balance DESC) AS regional_rank
            FROM ACCOUNTS a
            JOIN BRANCHES b ON a.branch_code = b.branch_code
            WHERE a.status = 'ACTIVE'
            ORDER BY b.region, regional_rank
        """).fetchall()

        # Running balance for top active account (1001)
        running_bal = conn.execute("""
            SELECT 
                txn_id,
                txn_date,
                from_account,
                to_account,
                txn_type,
                amount,
                SUM(CASE 
                    WHEN to_account = 1001 THEN amount 
                    WHEN from_account = 1001 THEN -amount 
                    ELSE 0 
                END) OVER (ORDER BY txn_id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_flow
            FROM TRANSACTIONS
            WHERE from_account = 1001 OR to_account = 1001
            ORDER BY txn_id DESC
        """).fetchall()

        conn.close()
        return {
            "wealth_ranks": [dict(r) for r in wealth_ranks],
            "running_balance_1001": [dict(r) for r in running_bal]
        }

    @staticmethod
    def get_fraud_alerts(limit=50):
        conn = get_connection()
        alerts = conn.execute("SELECT * FROM FRAUD_ALERTS ORDER BY alert_id DESC LIMIT ?", (limit,)).fetchall()
        conn.close()
        return [dict(a) for a in alerts]

    @staticmethod
    def get_distributed_txns(limit=50):
        conn = get_connection()
        dtxns = conn.execute("SELECT * FROM DISTRIBUTED_TXN_LOG ORDER BY dtxn_id DESC LIMIT ?", (limit,)).fetchall()
        conn.close()
        return [dict(d) for d in dtxns]

    @staticmethod
    def get_transactions(limit=50):
        conn = get_connection()
        txns = conn.execute("SELECT * FROM TRANSACTIONS ORDER BY txn_id DESC LIMIT ?", (limit,)).fetchall()
        conn.close()
        return [dict(t) for t in txns]

    @staticmethod
    def get_audit_logs(limit=50):
        conn = get_connection()
        logs = conn.execute("SELECT * FROM AUDIT_LOGS ORDER BY log_id DESC LIMIT ?", (limit,)).fetchall()
        conn.close()
        return [dict(l) for l in logs]

    @staticmethod
    def get_stats():
        conn = get_connection()
        total_balance = conn.execute("SELECT COALESCE(SUM(balance), 0) FROM ACCOUNTS").fetchone()[0]
        total_accounts = conn.execute("SELECT COUNT(*) FROM ACCOUNTS").fetchone()[0]
        total_txns = conn.execute("SELECT COUNT(*) FROM TRANSACTIONS").fetchone()[0]
        total_audits = conn.execute("SELECT COUNT(*) FROM AUDIT_LOGS").fetchone()[0]
        total_frauds = conn.execute("SELECT COUNT(*) FROM FRAUD_ALERTS").fetchone()[0]
        total_dtxns = conn.execute("SELECT COUNT(*) FROM DISTRIBUTED_TXN_LOG").fetchone()[0]
        conn.close()
        return {
            "total_balance": total_balance,
            "total_accounts": total_accounts,
            "total_transactions": total_txns,
            "total_audit_events": total_audits,
            "total_fraud_alerts": total_frauds,
            "total_distributed_txns": total_dtxns
        }
