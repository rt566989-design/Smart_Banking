# 🏛️ Smart Banking & Fund Transfer System (ADBMS & Oracle PL/SQL Enterprise Suite)

An advanced, comprehensive **Advanced Database Management Systems (ADBMS) + Oracle PL/SQL Mini Project** combining modern database engineering, Object-Relational features, partitioned distributed banking, high-performance bulk bindings, and an interactive full-stack web dashboard.

---

## 📁 Project Architecture & File Directory

### 🌟 Advanced ADBMS & PL/SQL Suite (Synchronized Everywhere)

| File Name | Purpose & ADBMS Concepts Demonstrated |
| :--- | :--- |
| [`all_in_one_run.sql`](all_in_one_run.sql) / [`adbms_all_in_one_master.sql`](adbms_all_in_one_master.sql) | **Master 1-Click Script**: Oracle Live SQL, SQL Developer, or SQL*Plus ready |
| [`01_schema.sql`](01_schema.sql) / [`01_adbms_schema.sql`](01_adbms_schema.sql) | **ORDBMS User Types** (`ADDRESS_TYP`, `KYC_DOC_TYP`), VARRAYs, **Range Partitioned** Transactions & **List Partitioned** Accounts |
| [`02_adbms_indexing_mviews.sql`](02_adbms_indexing_mviews.sql) | **Advanced Indexing** (Bitmap, Function-Based, Composite) & **Materialized Views** with Fast Refresh Logs |
| [`02_triggers.sql`](02_triggers.sql) / [`03_adbms_compound_triggers.sql`](03_adbms_compound_triggers.sql) | **Autonomous Transactions** (`PRAGMA AUTONOMOUS_TRANSACTION`) & **Compound Trigger** (Bypassing `ORA-04091` Mutating Table Error) |
| [`03_package_spec.sql`](03_package_spec.sql) / [`04_adbms_package_spec.sql`](04_adbms_package_spec.sql) | Package Spec: Bulk Collect routines, Pipelined Table Functions, and Distributed 2PC Simulator |
| [`04_package_body.sql`](04_package_body.sql) / [`05_adbms_package_body.sql`](05_adbms_package_body.sql) | Package Body: `BULK COLLECT` + `FORALL ... SAVE EXCEPTIONS`, Row Locking (`FOR UPDATE WAIT 5`), and Pipelined streaming |
| [`06_adbms_olap_analytics.sql`](06_adbms_olap_analytics.sql) | **OLAP Window Functions**: `RANK`, `DENSE_RANK`, Runtime Running Balances, `LEAD`/`LAG` Anomaly Velocity, and `ROLLUP`/`CUBE` |
| [`05_sample_data.sql`](05_sample_data.sql) / [`07_adbms_sample_data.sql`](07_adbms_sample_data.sql) | Multi-Branch network seed data (Delhi, Mumbai, Bangalore, Kolkata) spanning multi-quarter partitions |
| [`06_test_cases.sql`](06_test_cases.sql) / [`08_adbms_test_suite.sql`](08_adbms_test_suite.sql) | Automated test suite validating all 8 ADBMS scenarios end-to-end |
| [`ADBMS_PLSQL_PROJECT_REPORT.md`](ADBMS_PLSQL_PROJECT_REPORT.md) | **Complete Academic Project Report & Viva / Interview Guide** with ER diagrams and 15+ solved questions |

### 💻 Full-Stack Application, In-IDE Runners & Simulators

| File Name | Purpose |
| :--- | :--- |
| [`run_project.py`](run_project.py) | **In-IDE 1-Click Play Button Runner**: Executes all 8 ADBMS modules and prints a formatted terminal report |
| [`run_banking.py`](run_banking.py) | **Terminal ADBMS PL/SQL Executor**: Runs atomic operations, autonomous alerts, and bulk processing in console |
| [`simulate_banking.py`](simulate_banking.py) | **Interactive Console Simulator**: Interactive CLI menu (0-11) for testing 2PC, partitions, and triggers |
| [`Start_Banking_Project.bat`](Start_Banking_Project.bat) | **1-Click Windows Launcher** (Launches server & opens browser dashboard automatically) |
| [`run_fullstack.py`](run_fullstack.py) / [`app.py`](app.py) | Python full-stack runners hosting the REST API and modern glassmorphic web dashboard |
| [`backend/app.py`](backend/app.py) | Flask REST API controller connecting the web dashboard with the ADBMS banking engine |
| [`backend/banking_engine.py`](backend/banking_engine.py) | Python business engine executing ACID locks, autonomous fraud alerts, 2PC, and partitioning |
| [`backend/database.py`](backend/database.py) | Database manager initializing SQLite partitions, audit ledgers, and materialized view tables |
| [`frontend/index.html`](frontend/index.html) | Modern dark-mode web application featuring the interactive **⚡ ADBMS Hub** |

---

## 🧩 Key ADBMS + PL/SQL Concepts Implemented

1. **Object-Relational DBMS (ORDBMS)**:
   - User-defined Object Types (`ADDRESS_TYP`) with member methods (`get_full_address()`).
   - Structured KYC documents (`KYC_DOC_TYP`) and in-row collections (`PHONE_ARRAY_TYP AS VARRAY(3)`).
2. **Table Partitioning & Partition Pruning**:
   - `TRANSACTIONS_PARTITIONED`: Partitioned by `RANGE (txn_date)` into historical quarters (`p_2025_q1` to `p_future`).
   - `ACCOUNTS_PARTITIONED`: Partitioned by `LIST (account_type)` into `SAVINGS`, `CURRENT`, and `SALARY`.
   - **Partition Pruning**: Query execution plans skip entire unneeded disk partitions during date range lookups.
3. **Compound Triggers (Bypassing Mutating Table Error `ORA-04091`)**:
   - Enforces daily transaction ceiling (₹50,000/day).
   - Solves the mutating table error using 4 execution phases (`BEFORE STATEMENT`, `BEFORE EACH ROW`, `AFTER EACH ROW`, `AFTER STATEMENT`) and PGA memory arrays.
4. **Autonomous Transactions (`PRAGMA AUTONOMOUS_TRANSACTION`)**:
   - Security incidents and fraud alerts are written in an independent commit scope.
   - Even when a malicious transfer aborts and triggers `ROLLBACK`, the forensic log in `FRAUD_ALERTS` is permanently retained.
5. **High-Performance Bulk Operations (`BULK COLLECT` & `FORALL`)**:
   - Eliminates slow-by-slow row iteration and CPU context switching between PL/SQL and SQL engines.
   - Accelerates batch interest and maintenance fee deductions by **20x to 50x**.
6. **Materialized Views with Fast Refresh (OLAP / Data Warehousing)**:
   - `MV_DAILY_BRANCH_SUMMARY` & `MV_CUSTOMER_NETWORTH` precompute branch liquidity and customer tiers for instant retrieval.
7. **Distributed Two-Phase Commit (2PC) Banking Simulator**:
   - Simulates distributed banking across remote branch nodes (Branch Delhi &rarr; Branch Bangalore).
   - Coordinates Phase 1 (Prepare / Balance Reservation) and Phase 2 (Global Commit or Rollback).
8. **OLAP Analytical SQL**:
   - `RANK()` and `DENSE_RANK()` for regional wealth classification.
   - Cumulative runtime running balances via `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`.
   - Rapid anomaly velocity detection using `LEAD()` and `LAG()`.

---

## 🚀 How to Run the Project

### Method 1: Interactive Full-Stack Web Dashboard (1-Click Run)
1. Double-click [`Start_Banking_Project.bat`](Start_Banking_Project.bat) OR run in your terminal:
   ```bash
   python run_fullstack.py
   ```
2. The browser opens automatically at `http://127.0.0.1:5000`.
3. Test all features visually:
   - Transfer funds with row-level locks and ACID savepoints.
   - Open the **⚡ ADBMS Hub** tab to test partition pruning, trigger the compound trigger daily cap, simulate autonomous fraud alerts, execute bulk processing batches, and run 2PC distributed transfers.

### Method 2: Pure Oracle Database (Oracle Live SQL / SQL Developer)
1. Open [Oracle Live SQL](https://livesql.oracle.com/) or Oracle SQL Developer.
2. Copy and paste the entire content of [`adbms_all_in_one_master.sql`](adbms_all_in_one_master.sql).
3. Click **Run Script (F5)** to execute the entire schema, compile packages, seed multi-branch data, and run all 8 automated tests.

---

## 📚 Academic Project Documentation & Viva Guide
Read the complete project synopsis, architectural diagrams, and 15+ university examination questions and answers in:
👉 [`ADBMS_PLSQL_PROJECT_REPORT.md`](ADBMS_PLSQL_PROJECT_REPORT.md)
