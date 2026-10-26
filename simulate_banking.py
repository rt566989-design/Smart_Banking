"""
=============================================================================
SMART BANKING & ENTERPRISE FUND TRANSFER SYSTEM - INTERACTIVE CLI SIMULATOR
Demonstrates ADBMS and Oracle PL/SQL concepts in an interactive console menu.
Command: python simulate_banking.py
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

def clear_screen():
    print("\n" * 2)

def print_banner():
    print("=" * 78)
    print("      🏛️  APEXBANK: ADBMS & PL/SQL INTERACTIVE CONSOLE TERMINAL")
    print("      Multi-Branch Core | Autonomous Transactions | Partitioning | 2PC")
    print("=" * 78)

def show_accounts():
    accounts = BankingEngine.get_all_accounts()
    print("\n--- ACTIVE ACCOUNTS (MULTI-BRANCH) ---")
    print(f"{'Acc No':<8} | {'Holder Name':<20} | {'Branch Name':<24} | {'Type':<9} | {'Balance'}")
    print("-" * 80)
    for a in accounts:
        print(f"{a['account_no']:<8} | {a['holder_name']:<20} | {a.get('branch_name', 'Main'):<24} | {a['account_type']:<9} | ₹{a['balance']:,.2f}")
    print()

def main_menu():
    init_database()
    while True:
        print_banner()
        print("  1. 📋 View All Accounts & Regional Branches")
        print("  2. 💵 Deposit Funds (Atomic ACID)")
        print("  3. 🏧 Withdraw Funds (Subject to Daily Limit)")
        print("  4. 🔁 Transfer Funds (Inter-Account ACID Transaction)")
        print("  5. 🚨 Test Daily Limit Breach (Triggers Autonomous Fraud Alert)")
        print("  6. 🌐 Run Distributed Two-Phase Commit (2PC Delhi -> Mumbai)")
        print("  7. ⚡ Run High-Speed Bulk Interest Processing (BULK COLLECT & FORALL)")
        print("  8. 📂 Query Partitioned Transactions (Range Partition Pruning)")
        print("  9. 📊 Query Materialized Views (Branch Liquidity Precomputed Disk Table)")
        print(" 10. 📈 Query OLAP Window Functions (Regional Wealth DENSE_RANK)")
        print(" 11. 🔄 Reset Database to Clean Multi-Branch Seed Data")
        print("  0. ❌ Exit")
        print("=" * 78)

        choice = input("Select an option (0-11): ").strip()

        if choice == '1':
            show_accounts()
        elif choice == '2':
            show_accounts()
            try:
                acc = int(input("Enter Account Number: "))
                amt = float(input("Enter Deposit Amount (₹): "))
                res = BankingEngine.deposit(acc, amt, "Console Deposit")
                print(f"\n✔ Success! Credited ₹{res['deposited']:,.2f}. New Balance: ₹{res['new_balance']:,.2f}\n")
            except Exception as e:
                print(f"\n❌ Error: {e}\n")
        elif choice == '3':
            show_accounts()
            try:
                acc = int(input("Enter Account Number: "))
                amt = float(input("Enter Withdrawal Amount (₹): "))
                res = BankingEngine.withdraw(acc, amt, "Console Withdrawal")
                print(f"\n✔ Success! Debited ₹{res['withdrawn']:,.2f}. New Balance: ₹{res['remaining_balance']:,.2f}\n")
            except Exception as e:
                print(f"\n❌ [EXCEPTION]: {e}\n")
        elif choice == '4':
            show_accounts()
            try:
                f_acc = int(input("Enter Sender Account Number: "))
                t_acc = int(input("Enter Receiver Account Number: "))
                amt = float(input("Enter Transfer Amount (₹): "))
                res = BankingEngine.transfer_funds(f_acc, t_acc, amt, "Console Transfer")
                print(f"\n✔ Success! Transferred ₹{amt:,.2f} from Acc #{f_acc} to Acc #{t_acc}.\n")
            except Exception as e:
                print(f"\n❌ [EXCEPTION]: {e}\n")
        elif choice == '5':
            print("\nSimulating Breach: Attempting ₹70,000 withdrawal on Acc #1004 (Daily Limit: ₹50,000)...")
            try:
                BankingEngine.withdraw(1004, 70000.0, "Daily Limit Breach Test")
            except Exception as e:
                print(f"✔ Intercepted by Compound Trigger: {e}")
            alerts = BankingEngine.get_fraud_alerts(limit=1)
            if alerts:
                a = alerts[0]
                print(f"✔ Autonomous Transaction Logged: Alert #{a['alert_id']} | Severity: {a['severity']} | Reason: {a['reason']}\n")
        elif choice == '6':
            print("\nExecuting Distributed 2PC: Branch Delhi (BR-DEL-01) -> Branch Mumbai (BR-MUM-01)...")
            try:
                res = BankingEngine.simulate_distributed_transfer("BR-DEL-01", "BR-MUM-01", 1001, 1002, 10000.0)
                print(f"✔ 2PC Completed: Global XID = {res['global_xid']} | Status = {res['status']}\n")
            except Exception as e:
                print(f"❌ 2PC Failed: {e}\n")
        elif choice == '7':
            rate = float(input("Enter Annual Interest Rate (%) [Default: 4.5]: ") or 4.5)
            res = BankingEngine.bulk_apply_monthly_interest(annual_rate=rate)
            print(f"\n✔ BULK COLLECT & FORALL Finished in {res['elapsed_ms']} ms!")
            print(f"  Credited {res['accounts_credited']} accounts with ₹{res['total_interest_paid']:,.2f}\n")
        elif choice == '8':
            part = input("Enter partition name (e.g. P_2025_Q1, P_2025_Q2, or ALL): ").strip().upper() or "ALL"
            txns = BankingEngine.get_partitioned_transactions(partition=part)
            print(f"\n--- PARTITIONED TRANSACTIONS ({part}) ---")
            for t in txns[:6]:
                print(f"Txn #{t['txn_id']} | {t['txn_date']} | Part: {t['partition_name']} | Type: {t['txn_type']} | ₹{t['amount']:,.2f}")
            print()
        elif choice == '9':
            mviews = BankingEngine.get_branch_summary_mview()
            print("\n--- MATERIALIZED VIEW: MV_DAILY_BRANCH_SUMMARY ---")
            print(f"{'Branch Code':<14} | {'Branch Name':<24} | {'Region':<8} | {'Total Liquidity'}")
            print("-" * 65)
            for m in mviews:
                print(f"{m['branch_code']:<14} | {m['branch_name']:<24} | {m['region']:<8} | ₹{m['total_branch_liquidity']:,.2f}")
            print()
        elif choice == '10':
            olap = BankingEngine.get_olap_analytics()
            print("\n--- OLAP WINDOW FUNCTION: DENSE_RANK() REGIONAL WEALTH ---")
            for r in olap.get("wealth_ranks", [])[:6]:
                print(f"Rank #{r['regional_rank']} | {r['holder_name']:<18} | Region: {r['region']:<6} | Balance: ₹{r['balance']:,.2f}")
            print()
        elif choice == '11':
            init_database()
            print("\n✔ Database has been reset to clean multi-branch ADBMS seed state!\n")
        elif choice == '0':
            print("\nExiting ApexBank Terminal. Thank you!\n")
            break
        else:
            print("\nInvalid choice. Please select 0 to 11.\n")
        
        input("Press Enter to continue...")

if __name__ == "__main__":
    main_menu()
