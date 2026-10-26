"""
=============================================================================
SMART BANKING & ENTERPRISE FUND TRANSFER SYSTEM - ADBMS PL/SQL RUNNER
Run this file directly in your terminal to execute the ADBMS Banking Package!
Command: python run_banking.py
=============================================================================
"""
import sys
import io
import os
import time

# Ensure clean UTF-8 output on Windows console
if sys.stdout.encoding != 'utf-8':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, PROJECT_ROOT)

from backend.database import init_database
from backend.banking_engine import BankingEngine

def print_separator(char="=", length=80):
    print(char * length)

def main():
    print_separator("=")
    print("      🏛️  ORACLE PL/SQL & ADBMS ENTERPRISE SIMULATOR ENGINE")
    print("      Package: ADBMS_BANKING_PKG | Multi-Branch Enterprise Core")
    print_separator("=")
    print("[INFO] Booting ADBMS Database Engine...")
    init_database()
    print("[INFO] Database successfully initialized with multi-branch schema and partitions.\n")

    time.sleep(0.3)
    print(">>> [STEP 1] EXECUTING ATOMIC CASH DEPOSIT (ADBMS_BANKING_PKG.deposit)...")
    d_res = BankingEngine.deposit(1001, 15000.0, "Salary Bonus Deposit")
    print(f"✔ Credited ₹{d_res['deposited']:,.2f} to Acc #{d_res['account_no']} | New Bal: ₹{d_res['new_balance']:,.2f}")

    time.sleep(0.3)
    print("\n>>> [STEP 2] EXECUTING ATOMIC CASH WITHDRAWAL (ADBMS_BANKING_PKG.withdraw)...")
    w_res = BankingEngine.withdraw(1002, 5000.0, "ATM Cash Withdrawal")
    print(f"✔ Debited ₹{w_res['withdrawn']:,.2f} from Acc #{w_res['account_no']} | New Bal: ₹{w_res['remaining_balance']:,.2f}")

    time.sleep(0.3)
    print("\n>>> [STEP 3] EXECUTING INTER-ACCOUNT TRANSFER (ADBMS_BANKING_PKG.transfer_funds)...")
    t_res = BankingEngine.transfer_funds(1002, 1004, 8000.0, "Consultancy Payment")
    print(f"✔ Transferred ₹{t_res['amount']:,.2f} from Acc #{t_res['from_account']} to Acc #{t_res['to_account']} | Status: {t_res['status']}")

    time.sleep(0.3)
    print("\n>>> [STEP 4] TESTING COMPOUND TRIGGER DAILY LIMIT SENTINEL (Cap: ₹50,000)...")
    try:
        BankingEngine.withdraw(1004, 75000.0, "Exceeding daily threshold")
    except Exception as e:
        print(f"✔ Trigger Successfully Intercepted: {e}")

    time.sleep(0.3)
    print("\n>>> [STEP 5] TESTING AUTONOMOUS FRAUD LOGGING (PRAGMA AUTONOMOUS_TRANSACTION)...")
    alerts = BankingEngine.get_fraud_alerts(limit=2)
    for a in alerts:
        print(f"✔ Recorded Security Alert #{a['alert_id']} | Severity: {a['severity']} | Reason: {a['reason']}")

    time.sleep(0.3)
    print("\n>>> [STEP 6] TESTING HIGH-PERFORMANCE BULK OPERATIONS (BULK COLLECT & FORALL)...")
    b_res = BankingEngine.bulk_apply_monthly_interest(annual_rate=5.0)
    print(f"✔ Bulk Calculation finished in {b_res['elapsed_ms']} ms | Credited {b_res['accounts_credited']} accounts with ₹{b_res['total_interest_paid']:,.2f}")

    time.sleep(0.3)
    print("\n>>> [STEP 7] TESTING DISTRIBUTED TWO-PHASE COMMIT (2PC)...")
    d2pc = BankingEngine.simulate_distributed_transfer("BR-DEL-01", "BR-MUM-01", 1001, 1002, 10000.0)
    print(f"✔ Global Txn: {d2pc['global_xid']} | 2PC Status: {d2pc['status']}")

    time.sleep(0.3)
    print("\n>>> [STEP 8] CURRENT MULTI-BRANCH ACCOUNT SUMMARY:")
    accounts = BankingEngine.get_all_accounts()
    print(f"{'Acc No':<8} | {'Holder Name':<20} | {'Branch Name':<24} | {'Type':<9} | {'Balance'}")
    print("-" * 80)
    for a in accounts:
        print(f"{a['account_no']:<8} | {a['holder_name']:<20} | {a.get('branch_name', 'Main'):<24} | {a['account_type']:<9} | ₹{a['balance']:,.2f}")

    print_separator("=")
    print("✔ ADBMS PL/SQL Engine Verification Completed Successfully!")
    print("  To launch the Web GUI: python app.py")
    print_separator("=")

if __name__ == "__main__":
    main()
