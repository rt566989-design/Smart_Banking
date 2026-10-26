# Smart Banking & Fund Transfer System (PL/SQL Mini Project)

Ek comprehensive **Oracle PL/SQL Mini Project** jo banking operations, atomic fund transfers, automated interest calculations, aur security audit trails ko demonstrate karta hai.

---

## 📁 Project Structure

| File Name | Purpose |
| :--- | :--- |
| [`01_schema.sql`](01_schema.sql) | Tables (`ACCOUNTS`, `TRANSACTIONS`, `AUDIT_LOGS`), Sequences, Constraints |
| [`02_triggers.sql`](02_triggers.sql) | Automated Audit Trigger (`TRG_ACCOUNT_AUDIT`) & Safety Trigger (`TRG_PREVENT_DELETE_ACTIVE`) |
| [`03_package_spec.sql`](03_package_spec.sql) | Package Specification (`BANKING_PKG`) with custom exceptions |
| [`04_package_body.sql`](04_package_body.sql) | Package Body with business logic, Cursors, and Exception Handling |
| [`05_sample_data.sql`](05_sample_data.sql) | Initial seed data (4 sample bank accounts) |
| [`06_test_cases.sql`](06_test_cases.sql) | Simulation scripts to test deposits, transfers, exceptions, and audit logs |
| [`all_in_one_run.sql`](all_in_one_run.sql) | **Single-file version** (Copy-paste directly into Oracle Live SQL or SQL Developer) |

---

## 🧩 Key PL/SQL Concepts Covered

1. **Package Architecture (`BANKING_PKG`)**:
   - Clean encapsulation with separate **Specification** and **Body**.
2. **Transaction Control (ACID Compliance)**:
   - `SAVEPOINT sp_before_transfer;`
   - `ROLLBACK TO sp_before_transfer;`
   - `COMMIT;`
   - Row-level pessimistic locking via `SELECT ... FOR UPDATE` (concurrency protection).
3. **Triggers**:
   - `TRG_ACCOUNT_AUDIT`: Automatic real-time ledger recording whenever an account balance or status changes.
   - `TRG_PREVENT_DELETE_ACTIVE`: Business constraint to block deleting active accounts with a positive balance.
4. **Cursors**:
   - Explicit Cursor with `FOR UPDATE OF balance` and `WHERE CURRENT OF c_savings` in `apply_monthly_interest`.
   - Cursor FOR Loop with formatted tabular printing in `print_mini_statement`.
5. **Exception Handling**:
   - Custom exceptions (`e_insufficient_funds`, `e_account_inactive`, `e_same_account`, `e_invalid_amount`) mapped to error numbers via `PRAGMA EXCEPTION_INIT`.
   - `RAISE_APPLICATION_ERROR` with custom messages.

---

## 🚀 Kaise Run Karein (Execution Steps)

### Option A: 1-Click Run (Fastest)
1. Oracle SQL Developer, SQL*Plus, ya [Oracle Live SQL](https://livesql.oracle.com/) open karein.
2. File [`all_in_one_run.sql`](all_in_one_run.sql) ka sara content copy karke Run/Execute (F5) press kar dein.

### Option B: Step-by-Step Run
Run the files in this exact sequence:
```sql
@01_schema.sql
@02_triggers.sql
@03_package_spec.sql
@04_package_body.sql
@05_sample_data.sql
@06_test_cases.sql
```

---

## 🎯 Viva / Interview Questions & Answers

### Q1: Package use karne ka kya fayda hai? Standalone procedure kyun nahi banaya?
> **Answer:** Packages PL/SQL me modularity, encapsulation aur better performance provide karte hain. Package ka specification aur body alag hota hai, jisse implementation hide rehti hai. Saath hi, jab package ka koi program call hota hai, pura package memory (SGA) me ek saath load ho jata hai, jisse subsequent calls fast ho jati hain.

### Q2: Fund Transfer me Row-Level Locking (`FOR UPDATE`) kyun zaroori hai?
> **Answer:** Agar do transactions simultaneously ek hi account se paisa withdraw karne ki koshish karein (race condition), toh balance negative ho sakta hai. `SELECT ... FOR UPDATE` row ko lock kar deta hai jab tak transaction `COMMIT` ya `ROLLBACK` na ho jaye.

### Q3: `SAVEPOINT` ka use kyun kiya gaya hai?
> **Answer:** `transfer_funds` procedure me agar receiver ke account me credit karte waqt koi error aa jaye, toh hum `ROLLBACK TO sp_before_transfer` karte hain taaki sender ka paisa deduct na rahe aur pure operation ka state wapis safe ho jaye. Iske baad failed transaction ka log insert karke clean state maintain ki jati hai.

### Q4: `WHERE CURRENT OF cursor_name` kya karta hai?
> **Answer:** Jab hum `FOR UPDATE` cursor use karte hain, toh `UPDATE table_name SET ... WHERE CURRENT OF cursor_name` ka use karke hum specifically usi exact row ko update kar sakte hain jisko cursor abhi fetch kar raha hai, bina primary key dobara match kiye.

### Q5: Trigger se audit trail kaise ban rahi hai?
> **Answer:** `TRG_ACCOUNT_AUDIT` trigger `AFTER UPDATE OF balance ON ACCOUNTS` par fire hota hai. `:OLD.balance` aur `:NEW.balance` ko compare karke automatically `AUDIT_LOGS` table me timestamp aur user ke sath change record kar deta hai. Isse fraud detection aur financial audit easily ho jata hai.
