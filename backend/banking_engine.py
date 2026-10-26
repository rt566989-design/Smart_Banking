"""
Banking Business Engine (Equivalent to Oracle BANKING_PKG)
Implements all procedures, functions, transactions, and custom exception codes.
"""
from backend.database import get_connection

class BankingEngine:
    @staticmethod
    def get_all_accounts():
        conn = get_connection()
        accounts = conn.execute("SELECT * FROM ACCOUNTS ORDER BY account_no ASC").fetchall()
        conn.close()
        return [dict(a) for a in accounts]

    @staticmethod
    def get_account_by_id(account_no):
        conn = get_connection()
        acc = conn.execute("SELECT * FROM ACCOUNTS WHERE account_no = ?", (account_no,)).fetchone()
        conn.close()
        return dict(acc) if acc else None

    @staticmethod
    def open_account(name, email, phone, acc_type, initial_deposit):
        if initial_deposit < 0:
            raise ValueError("ORA-20004: Initial deposit cannot be negative.")

        conn = get_connection()
        cur = conn.cursor()
        try:
            cur.execute("""
                INSERT INTO ACCOUNTS (holder_name, email, phone, account_type, balance, status)
                VALUES (?, ?, ?, ?, ?, 'ACTIVE')
            """, (name.strip(), email.strip().lower(), phone.strip(), acc_type.upper(), initial_deposit))
            acc_no = cur.lastrowid

            if initial_deposit > 0:
                cur.execute("""
                    INSERT INTO TRANSACTIONS (to_account, txn_type, amount, status, remarks)
                    VALUES (?, 'DEPOSIT', ?, 'SUCCESS', 'Account Opening Deposit')
                """, (acc_no, initial_deposit))

            conn.commit()
            return {"account_no": acc_no, "holder_name": name, "balance": initial_deposit}
        except Exception as e:
            conn.rollback()
            raise e
        finally:
            conn.close()

    @staticmethod
    def deposit(account_no, amount, remarks="Cash Deposit"):
        if amount <= 0:
            raise ValueError("ORA-20004: Deposit amount must be greater than zero.")

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
            cur.execute("""
                INSERT INTO TRANSACTIONS (to_account, txn_type, amount, status, remarks)
                VALUES (?, 'DEPOSIT', ?, 'SUCCESS', ?)
            """, (account_no, amount, remarks))
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
            acc = cur.execute("SELECT balance, status FROM ACCOUNTS WHERE account_no = ?", (account_no,)).fetchone()
            if not acc:
                raise ValueError(f"ORA-20006: Account #{account_no} does not exist.")
            if acc["status"] != 'ACTIVE':
                raise ValueError(f"ORA-20003: Account #{account_no} is {acc['status']}.")
            if acc["balance"] < amount:
                raise ValueError(f"ORA-20002: Insufficient funds. Available: ₹{acc['balance']:,.2f}, Requested: ₹{amount:,.2f}")

            new_bal = acc["balance"] - amount
            cur.execute("UPDATE ACCOUNTS SET balance = ? WHERE account_no = ?", (new_bal, account_no))
            cur.execute("""
                INSERT INTO TRANSACTIONS (from_account, txn_type, amount, status, remarks)
                VALUES (?, 'WITHDRAWAL', ?, 'SUCCESS', ?)
            """, (account_no, amount, remarks))
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
            s_acc = cur.execute("SELECT balance, status FROM ACCOUNTS WHERE account_no = ?", (from_acc,)).fetchone()
            r_acc = cur.execute("SELECT balance, status FROM ACCOUNTS WHERE account_no = ?", (to_acc,)).fetchone()

            if not s_acc:
                raise ValueError(f"ORA-20006: Sender Account #{from_acc} not found.")
            if not r_acc:
                raise ValueError(f"ORA-20006: Receiver Account #{to_acc} not found.")

            if s_acc["status"] != 'ACTIVE':
                raise ValueError(f"ORA-20003: Sender Account #{from_acc} is {s_acc['status']}.")
            if r_acc["status"] != 'ACTIVE':
                raise ValueError(f"ORA-20003: Receiver Account #{to_acc} is {r_acc['status']}.")

            if s_acc["balance"] < amount:
                # Record Failed transaction attempt
                cur.execute("""
                    INSERT INTO TRANSACTIONS (from_account, to_account, txn_type, amount, status, remarks)
                    VALUES (?, ?, 'TRANSFER', ?, 'FAILED', 'ORA-20002: Insufficient balance')
                """, (from_acc, to_acc, amount))
                conn.commit()
                raise ValueError(f"ORA-20002: Insufficient funds in Acc #{from_acc}. Available: ₹{s_acc['balance']:,.2f}")

            # Atomic transfer
            cur.execute("UPDATE ACCOUNTS SET balance = balance - ? WHERE account_no = ?", (amount, from_acc))
            cur.execute("UPDATE ACCOUNTS SET balance = balance + ? WHERE account_no = ?", (amount, to_acc))
            cur.execute("""
                INSERT INTO TRANSACTIONS (from_account, to_account, txn_type, amount, status, remarks)
                VALUES (?, ?, 'TRANSFER', ?, 'SUCCESS', ?)
            """, (from_acc, to_acc, amount, remarks))
            conn.commit()
            return {"from_account": from_acc, "to_account": to_acc, "amount": amount, "status": "SUCCESS"}
        except Exception as e:
            conn.rollback()
            raise e
        finally:
            conn.close()

    @staticmethod
    def apply_monthly_interest(annual_rate=4.5):
        conn = get_connection()
        cur = conn.cursor()
        try:
            savings = cur.execute("""
                SELECT account_no, balance FROM ACCOUNTS 
                WHERE account_type = 'SAVINGS' AND status = 'ACTIVE' AND balance > 0
            """).fetchall()

            total_paid = 0
            count = 0
            details = []

            for row in savings:
                acc_no = row["account_no"]
                bal = row["balance"]
                monthly_int = round((bal * (annual_rate / 100)) / 12, 2)
                if monthly_int > 0:
                    cur.execute("UPDATE ACCOUNTS SET balance = balance + ? WHERE account_no = ?", (monthly_int, acc_no))
                    cur.execute("""
                        INSERT INTO TRANSACTIONS (to_account, txn_type, amount, status, remarks)
                        VALUES (?, 'INTEREST', ?, 'SUCCESS', ?)
                    """, (acc_no, monthly_int, f"Monthly Interest @ {annual_rate}% P.A."))
                    total_paid += monthly_int
                    count += 1
                    details.append({"account_no": acc_no, "interest": monthly_int})

            conn.commit()
            return {"accounts_credited": count, "total_interest_paid": total_paid, "details": details}
        except Exception as e:
            conn.rollback()
            raise e
        finally:
            conn.close()

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
        conn.close()
        return {
            "total_balance": total_balance,
            "total_accounts": total_accounts,
            "total_transactions": total_txns,
            "total_audit_events": total_audits
        }
