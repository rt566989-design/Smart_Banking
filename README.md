# Smart Banking & Fund Transfer System (Oracle PL/SQL & Full-Stack Web App)

A comprehensive **Oracle PL/SQL Mini Project** demonstrating enterprise banking operations, ACID-compliant atomic fund transfers, automated interest calculation with cursors, security audit triggers, and a modern full-stack web dashboard.

---

## 📁 Project Structure

| File Name | Purpose |
| :--- | :--- |
| [`01_schema.sql`](01_schema.sql) | Tables (`ACCOUNTS`, `TRANSACTIONS`, `AUDIT_LOGS`), Sequences, and Integrity Constraints |
| [`02_triggers.sql`](02_triggers.sql) | Automated Audit Trigger (`TRG_ACCOUNT_AUDIT`) & Safety Trigger (`TRG_PREVENT_DELETE_ACTIVE`) |
| [`03_package_spec.sql`](03_package_spec.sql) | Package Specification (`BANKING_PKG`) declaring public procedures, functions, and custom exceptions |
| [`04_package_body.sql`](04_package_body.sql) | Package Body implementing business logic, row locking, cursors, and transaction management |
| [`05_sample_data.sql`](05_sample_data.sql) | Initial seed data (4 sample bank accounts across Savings, Salary, and Current accounts) |
| [`06_test_cases.sql`](06_test_cases.sql) | Comprehensive test scenarios covering deposits, transfers, overdraft exceptions, and audit logs |
| [`all_in_one_run.sql`](all_in_one_run.sql) | **Single-file version** (Copy and paste directly into Oracle Live SQL or SQL Developer) |
| [`run_fullstack.py`](run_fullstack.py) | Full-stack runner launching the Flask REST API & glassmorphic web dashboard |
| [`Start_Banking_Project.bat`](Start_Banking_Project.bat) | 1-Click Windows launcher script |

---

## 🧩 Key PL/SQL Concepts Implemented

1. **Package Architecture (`BANKING_PKG`)**:
   - Clean modularity with separate **Specification** and **Body**.
   - Encapsulation of internal operations with public interfaces.
2. **Transaction Control (ACID Compliance)**:
   - `SAVEPOINT sp_before_transfer;`
   - `ROLLBACK TO sp_before_transfer;`
   - `COMMIT;`
   - Row-level pessimistic locking via `SELECT ... FOR UPDATE` to eliminate concurrency issues and race conditions.
3. **Database Triggers**:
   - `TRG_ACCOUNT_AUDIT`: Real-time audit trail recording every balance or status change into `AUDIT_LOGS`.
   - `TRG_PREVENT_DELETE_ACTIVE`: Safety rule preventing deletion of active accounts with non-zero balances.
4. **Cursors**:
   - Explicit cursor with `FOR UPDATE OF balance` and `WHERE CURRENT OF c_savings` in `apply_monthly_interest`.
   - Cursor FOR Loop with formatted statement output in `print_mini_statement`.
5. **Exception Handling**:
   - Custom business exceptions (`e_insufficient_funds`, `e_account_inactive`, `e_same_account`, `e_invalid_amount`) mapped via `PRAGMA EXCEPTION_INIT`.
   - User-friendly error messaging with `RAISE_APPLICATION_ERROR`.

---

## 🚀 How to Run (Execution Steps)

### Method 1: Oracle SQL Developer / Oracle Live SQL (Pure PL/SQL)

#### Option A: 1-Click Run (Fastest)
1. Open Oracle SQL Developer, SQL*Plus, or [Oracle Live SQL](https://livesql.oracle.com/).
2. Copy the entire contents of [`all_in_one_run.sql`](all_in_one_run.sql) and click **Run Script (F5)**.

#### Option B: Step-by-Step Execution
Execute the SQL scripts in this exact order:
```sql
@01_schema.sql
@02_triggers.sql
@03_package_spec.sql
@04_package_body.sql
@05_sample_data.sql
@06_test_cases.sql
```

---

### Method 2: Modern Full-Stack Web Application (Local Python & Web UI)

You can also run the project locally with the included interactive web dashboard:

1. **Install Dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

2. **Launch the Application**:
   - Double-click [`Start_Banking_Project.bat`](Start_Banking_Project.bat) OR run:
   ```bash
   python run_fullstack.py
   ```

3. **Open the Dashboard**:
   - Navigate to `http://127.0.0.1:5000` in your web browser.
   - Test real-time transfers, deposits, withdrawals, trigger audits, and interest calculations visually.

---

## 🎯 Viva / Interview Questions & Answers

### Q1: What are the benefits of using a Package instead of standalone procedures?
> **Answer:** Packages provide modularity, encapsulation, information hiding, and superior performance in PL/SQL. A package cleanly separates the specification (interface) from the body (implementation), allowing internal logic changes without invalidating dependent objects. Additionally, when a package subprogram is first invoked, the entire package is loaded into the SGA (System Global Area) memory at once, minimizing subsequent disk I/O and accelerating future executions.

### Q2: Why is Row-Level Locking (`FOR UPDATE`) essential during fund transfers?
> **Answer:** When two or more concurrent transactions attempt to withdraw or transfer funds from the same account simultaneously (race condition), it can cause lost updates or result in negative balances. `SELECT ... FOR UPDATE` acquires an exclusive row-level pessimistic lock on the account record until the transaction executes `COMMIT` or `ROLLBACK`, preventing race conditions and ensuring strict ACID transaction compliance.

### Q3: Why is `SAVEPOINT` used in the transfer operation?
> **Answer:** In the `transfer_funds` procedure, if an error or unexpected condition occurs after debiting the sender but prior to crediting the receiver, `ROLLBACK TO sp_before_transfer` rolls back only the financial state to the point before the transfer started. This ensures sender funds are safely restored, while still allowing the procedure to log the failed transaction details into the audit ledger and gracefully handle the exception.

### Q4: What is the purpose of `WHERE CURRENT OF cursor_name`?
> **Answer:** When iterating over a cursor declared with `FOR UPDATE`, using `UPDATE table_name SET ... WHERE CURRENT OF cursor_name` allows direct, optimized modification of the exact row currently fetched by the cursor, eliminating the overhead of re-evaluating primary keys or searching the table again.

### Q5: How is the automated audit trail maintained using Triggers?
> **Answer:** The `TRG_ACCOUNT_AUDIT` trigger fires `AFTER UPDATE OF balance, status ON ACCOUNTS` for each row. By comparing `:OLD.balance` and `:NEW.balance`, it automatically captures the change type (`CREDIT_UPDATE` or `DEBIT_UPDATE`), the old and new balance amounts, the modifying database user, and the exact timestamp, inserting an immutable audit entry into `AUDIT_LOGS` for compliance and financial tracking.
