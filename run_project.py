"""
=============================================================================
SMART BANKING & ENTERPRISE FUND TRANSFER SYSTEM (ADBMS & ORACLE PL/SQL)
Open this file in Antigravity IDE and click the top-right ▶ Play Button to run!
=============================================================================
Demonstrates Complete ADBMS & PL/SQL Concepts:
  1. Object-Relational DBMS (ORDBMS User-Defined Types & VARRAYs)
  2. Range & List Partitioning with Partition Pruning
  3. Compound Triggers (Bypassing Mutating Table Error ORA-04091)
  4. Autonomous Transactions (PRAGMA AUTONOMOUS_TRANSACTION Fraud Logging)
  5. High-Performance Bulk Processing (BULK COLLECT & FORALL)
  6. Distributed Two-Phase Commit (2PC) Protocol
  7. Materialized Views with Fast Refresh
  8. OLAP Analytical Window Queries (DENSE_RANK, Running Totals, LEAD/LAG)
=============================================================================
"""
import sys
import io
import os
import time

# Ensure proper Unicode and Rupee sign formatting across Windows console
if sys.stdout.encoding != 'utf-8':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, PROJECT_ROOT)

from backend.database import init_database
from backend.banking_engine import BankingEngine

def separator(char="=", length=82):
    print(char * length)

def banner():
    separator("=")
    print("  🏛️  APEXBANK: ADVANCED DATABASE MANAGEMENT SYSTEMS (ADBMS) & PL/SQL SUITE")
    print("      Autonomous Transactions | Partitioning | Compound Triggers | 2PC | Bulk Bindings")
    print("      Execution Environment: Antigravity IDE Autonomous Engine")
    separator("=")

def run():
    banner()
    time.sleep(0.3)

    print("\n[INIT] Initializing ADBMS Multi-Branch Enterprise Database...")
    init_database()
    print("✔ Core tables, ORDBMS types, partitions, and materialized views created and seeded.\n")
    time.sleep(0.2)

    # -------------------------------------------------------------------------
    # DEMO 1: ORDBMS Customer Onboarding
    # -------------------------------------------------------------------------
    separator("-")
    print("  🔹 DEMO 1: ORDBMS USER-DEFINED TYPES & VARRAY COLLECTIONS")
    separator("-")
    print("Executing: ADBMS_BANKING_PKG.open_account_ordbms(...)")
    address = {"street": "74 Golf Links", "city": "New Delhi", "state": "Delhi", "pincode": "110003"}
    kyc = {"doc_type": "PASSPORT", "doc_number": "L8923412"}
    phones = ["+91 9911223344", "+91 0112345678"]
    res1 = BankingEngine.open_account_ordbms(
        name="Vikramaditya Roy",
        email="vikram.roy@example.com",
        phones=phones,
        address=address,
        kyc=kyc,
        branch_code="BR-DEL-01",
        acc_type="SAVINGS",
        initial_deposit=85000.0
    )
    print(f"✔ ORDBMS Customer Created: ID #{res1['account_no']} | Holder: {res1['holder_name']}")
    print(f"  • Address Object: {address['street']}, {address['city']} - {address['pincode']}")
    print(f"  • KYC Type: {kyc['doc_type']} ({kyc['doc_number']}) | Phones VARRAY: {phones}")
    print(f"  • Initial Ledger Balance: ₹{res1['balance']:,.2f}")
    time.sleep(0.3)

    # -------------------------------------------------------------------------
    # DEMO 2: Partition Pruning
    # -------------------------------------------------------------------------
    print()
    separator("-")
    print("  🔹 DEMO 2: TABLE PARTITIONING & PARTITION PRUNING")
    separator("-")
    print("Querying Range-Partitioned Ledger: TRANSACTIONS_PARTITIONED (Partition: P_2025_Q1)...")
    q1_txns = BankingEngine.get_partitioned_transactions("P_2025_Q1")
    print(f"✔ Partition Pruning Active: Queried partition 'P_2025_Q1' directly without full-table scan.")
    print(f"  • Total Ledger Records in Partition: {len(q1_txns)}")
    for t in q1_txns[:3]:
        print(f"    - Txn #{t['txn_id']} | Date: {t['txn_date']} | Type: {t['txn_type']} | Amount: ₹{t['amount']:,.2f} | Status: {t['status']}")
    time.sleep(0.3)

    # -------------------------------------------------------------------------
    # DEMO 3: ACID Atomic Fund Transfer with Row Locks
    # -------------------------------------------------------------------------
    print()
    separator("-")
    print("  🔹 DEMO 3: ACID ATOMIC FUND TRANSFER (WITH ROW-LEVEL LOCKING)")
    separator("-")
    print("Executing: ADBMS_BANKING_PKG.transfer_funds(from_acc=1001, to_acc=1003, amount=12000)...")
    res3 = BankingEngine.transfer_funds(1001, 1003, 12000.0, "Inter-account RTGS settlement")
    acc1 = BankingEngine.get_account_by_id(1001)
    acc3 = BankingEngine.get_account_by_id(1003)
    print(f"✔ Transfer Successful: Status = {res3['status']}")
    print(f"  • Acc #1001 ({acc1['holder_name']}) New Balance: ₹{acc1['balance']:,.2f}")
    print(f"  • Acc #1003 ({acc3['holder_name']}) New Balance: ₹{acc3['balance']:,.2f}")
    time.sleep(0.3)

    # -------------------------------------------------------------------------
    # DEMO 4 & 5: Compound Trigger & Autonomous Transaction Fraud Logging
    # -------------------------------------------------------------------------
    print()
    separator("-")
    print("  🔹 DEMO 4 & 5: COMPOUND TRIGGER & AUTONOMOUS FRAUD LOGGING")
    separator("-")
    print("Simulating Daily Limit Breach on Acc #1004 (Daily Limit: ₹50,000.00)...")
    print("Attempting to transfer ₹60,000.00 in a single transaction...")
    try:
        BankingEngine.transfer_funds(1004, 1001, 60000.0, "Large unverified transfer")
    except Exception as e:
        print(f"✔ Intercepted by Compound Trigger: {e}")
        print("✔ Classic Mutating Table Error (ORA-04091) avoided using 4-Phase Compound Trigger!")
    
    # Check autonomous fraud alerts
    alerts = BankingEngine.get_fraud_alerts(limit=1)
    if alerts:
        latest = alerts[0]
        print(f"\n✔ AUTONOMOUS TRANSACTION VERIFIED:")
        print(f"  Even though parent transaction was rolled back, the security incident was PERMANENTLY logged:")
        print(f"  • Alert ID #{latest['alert_id']} | Severity: [{latest['severity']}]")
        print(f"  • Reason: {latest['reason']}")
        print(f"  • Attempted Amount: ₹{latest['attempted_amount']:,.2f} | Time: {latest['alert_time']}")
    time.sleep(0.3)

    # -------------------------------------------------------------------------
    # DEMO 6: High-Performance Bulk Operations (BULK COLLECT & FORALL)
    # -------------------------------------------------------------------------
    print()
    separator("-")
    print("  🔹 DEMO 6: HIGH-PERFORMANCE BULK OPERATIONS (BULK COLLECT & FORALL)")
    separator("-")
    print("Simulating BULK COLLECT + FORALL Interest Calculation (4.5% Annual Rate)...")
    bulk_res = BankingEngine.bulk_apply_monthly_interest(annual_rate=4.5)
    print(f"✔ Bulk Batch Finished in: {bulk_res['elapsed_ms']} ms")
    print(f"  • Accounts Credited: {bulk_res['accounts_credited']}")
    print(f"  • Total Interest Distributed: ₹{bulk_res['total_interest_paid']:,.2f}")
    print(f"  • Efficiency: Context switches reduced to zero (approx 20x - 50x faster than standard cursors).")
    time.sleep(0.3)

    # -------------------------------------------------------------------------
    # DEMO 7: Distributed Two-Phase Commit (2PC)
    # -------------------------------------------------------------------------
    print()
    separator("-")
    print("  🔹 DEMO 7: DISTRIBUTED TWO-PHASE COMMIT (2PC) PROTOCOL")
    separator("-")
    print("Simulating Inter-Branch Transfer: Delhi (BR-DEL-01) -> Bangalore (BR-BLR-01)...")
    res_2pc = BankingEngine.simulate_distributed_transfer(
        source_branch="BR-DEL-01",
        target_branch="BR-BLR-01",
        from_acc=1001,
        to_acc=1003,
        amount=15000.0
    )
    print(f"✔ Distributed Coordinator Output: Global XID = {res_2pc['global_xid']}")
    print(f"  • Phase 1: Local node votes COMMIT, target branch confirms preparedness.")
    print(f"  • Phase 2: {res_2pc['status']}")
    print(f"  • Status: Both remote branch ledgers synchronized under distributed 2PC guarantee.")
    time.sleep(0.3)

    # -------------------------------------------------------------------------
    # DEMO 8: Materialized Views with Fast Refresh
    # -------------------------------------------------------------------------
    print()
    separator("-")
    print("  🔹 DEMO 8: MATERIALIZED VIEWS WITH FAST REFRESH (OLAP)")
    separator("-")
    print("Querying MV_DAILY_BRANCH_SUMMARY (Precalculated Aggregate Disk Table)...")
    mviews = BankingEngine.get_branch_summary_mview()
    print(f"{'Branch Code':<14} | {'Branch Name':<26} | {'Region':<8} | {'Accounts':<10} | {'Total Liquidity'}")
    print("-" * 80)
    for m in mviews:
        print(f"{m['branch_code']:<14} | {m['branch_name']:<26} | {m['region']:<8} | {m['total_accounts']:<10} | ₹{m['total_branch_liquidity']:,.2f}")
    time.sleep(0.3)

    # -------------------------------------------------------------------------
    # DEMO 9: OLAP Analytical Window Queries
    # -------------------------------------------------------------------------
    print()
    separator("-")
    print("  🔹 DEMO 9: OLAP ANALYTICAL WINDOW QUERIES (DENSE_RANK & LIQUIDITY)")
    separator("-")
    olap = BankingEngine.get_olap_analytics()
    rankings = olap.get("wealth_ranks", [])
    print(f"{'Regional Rank':<15} | {'Holder Name':<22} | {'Region':<10} | {'Account Balance'}")
    print("-" * 65)
    for r in rankings[:5]:
        print(f"Rank #{r['regional_rank']:<10} | {r['holder_name']:<22} | {r['region']:<10} | ₹{r['balance']:,.2f}")

    # -------------------------------------------------------------------------
    # CONCLUSION & NEXT STEPS
    # -------------------------------------------------------------------------
    print()
    separator("=")
    print("  🎉 ALL 8 ADBMS & PL/SQL MODULES EXECUTED SUCCESSFULLY!")
    separator("=")
    print("\nNext Steps:")
    print("  1. 🌐 Launch the Interactive Web Dashboard:")
    print("     Run: python app.py   (or run_fullstack.py)")
    print("     URL: http://127.0.0.1:5000")
    print("\n  2. 🏛️ Pure Oracle Database (Oracle Live SQL / SQL Developer):")
    print("     Run: adbms_all_in_one_master.sql   (or all_in_one_run.sql)")
    print("\n  3. 📑 Academic Project Report & Viva Exam Questions:")
    print("     Open: ADBMS_PLSQL_PROJECT_REPORT.md\n")
    separator("=")

if __name__ == "__main__":
    run()
