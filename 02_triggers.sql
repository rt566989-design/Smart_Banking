-- =====================================================================
-- ADVANCED DATABASE MANAGEMENT SYSTEMS (ADBMS) & ORACLE PL/SQL
-- SMART BANKING & ENTERPRISE FUND TRANSFER SYSTEM
-- File: 03_adbms_compound_triggers.sql
-- Concepts Demonstrated:
--   1. Autonomous Transactions (PRAGMA AUTONOMOUS_TRANSACTION) for Security & Fraud Logging
--   2. Oracle COMPOUND TRIGGER to Eliminate Mutating Table Error (ORA-04091)
--   3. Row-Level Audit Triggers for Financial Ledger Integrity
--   4. Business Constraint Enforcement Triggers
-- =====================================================================

-- =====================================================================
-- SECTION 1: AUTONOMOUS TRANSACTION PROCEDURE FOR FRAUD/SECURITY LOGGING
-- =====================================================================
-- In ADBMS, Autonomous Transactions execute within an independent transaction
-- context. Even if the calling transaction rolls back (e.g. insufficient funds,
-- unauthorized transfer), the security alert is PERMANENTLY recorded!
CREATE OR REPLACE PROCEDURE LOG_FRAUD_ALERT_AUTONOMOUS (
    p_account_no       IN NUMBER,
    p_severity         IN VARCHAR2,
    p_reason           IN VARCHAR2,
    p_attempted_amount IN NUMBER,
    p_ip_address       IN VARCHAR2 DEFAULT '192.168.1.105'
) AS
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO FRAUD_ALERTS (
        alert_id,
        account_no,
        severity,
        reason,
        attempted_amount,
        ip_address,
        alert_time,
        resolved
    ) VALUES (
        SEQ_FRAUD_ID.NEXTVAL,
        p_account_no,
        UPPER(p_severity),
        p_reason,
        p_attempted_amount,
        p_ip_address,
        CURRENT_TIMESTAMP,
        'NO'
    );
    COMMIT; -- Commits ONLY this autonomous transaction, leaving parent transaction intact
END LOG_FRAUD_ALERT_AUTONOMOUS;
/

-- =====================================================================
-- SECTION 2: COMPOUND TRIGGER FOR DAILY LIMIT ENFORCEMENT
-- ELIMINATING THE MUTATING TABLE ERROR (ORA-04091)
-- =====================================================================
-- Business Requirement:
-- "Ensure no account exceeds its daily transaction limit in a single day."
--
-- Why standard row-level trigger fails:
-- Querying TRANSACTIONS inside a row-level trigger on TRANSACTIONS causes
-- ORA-04091 (table is mutating).
--
-- ADBMS Solution:
-- Compound Trigger aggregates data safely across 4 distinct phases:
--   1. BEFORE STATEMENT : Initialize collection
--   2. BEFORE EACH ROW  : Validate individual row inputs
--   3. AFTER EACH ROW   : Collect affected accounts into in-memory table
--   4. AFTER STATEMENT  : Query the table now that it has settled!
-- =====================================================================

CREATE OR REPLACE TRIGGER TRG_COMPOUND_DAILY_LIMIT
FOR INSERT ON TRANSACTIONS
COMPOUND TRIGGER

    -- Type and collection to store accounts affected in this DML statement
    TYPE t_account_list IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    g_affected_accounts t_account_list;
    g_count             PLS_INTEGER := 0;

    -- Phase 1: Before the statement executes
    BEFORE STATEMENT IS
    BEGIN
        g_affected_accounts.DELETE;
        g_count := 0;
    END BEFORE STATEMENT;

    -- Phase 2: After each row is inserted, buffer the source account ID
    AFTER EACH ROW IS
    BEGIN
        IF :NEW.from_account IS NOT NULL AND :NEW.txn_type IN ('WITHDRAWAL', 'TRANSFER') THEN
            g_count := g_count + 1;
            g_affected_accounts(g_count) := :NEW.from_account;
        END IF;
    END AFTER EACH ROW;

    -- Phase 3: After the statement finishes, the table is NO LONGER MUTATING!
    -- We can now safely query TRANSACTIONS with SUM() aggregates.
    AFTER STATEMENT IS
        v_daily_total NUMBER;
        v_daily_limit NUMBER;
        v_acc_no      NUMBER;
    BEGIN
        FOR i IN 1 .. g_count LOOP
            v_acc_no := g_affected_accounts(i);

            -- Fetch the account's configured daily transaction limit
            SELECT daily_limit INTO v_daily_limit
            FROM ACCOUNTS
            WHERE account_no = v_acc_no;

            -- Calculate total withdrawals/transfers already completed today
            SELECT NVL(SUM(amount), 0) INTO v_daily_total
            FROM TRANSACTIONS
            WHERE from_account = v_acc_no
              AND txn_type IN ('WITHDRAWAL', 'TRANSFER')
              AND status = 'SUCCESS'
              AND CAST(txn_date AS DATE) = TRUNC(SYSDATE);

            -- Enforce limit
            IF v_daily_total > v_daily_limit THEN
                -- Trigger autonomous fraud log before rejecting
                LOG_FRAUD_ALERT_AUTONOMOUS(
                    p_account_no       => v_acc_no,
                    p_severity         => 'HIGH',
                    p_reason           => 'Daily transaction limit of ₹' || v_daily_limit || ' breached! Attempted total: ₹' || v_daily_total,
                    p_attempted_amount => v_daily_total
                );

                RAISE_APPLICATION_ERROR(
                    -20010,
                    'Daily Transaction Limit Exceeded! Account ' || v_acc_no ||
                    ' has attempted total ₹' || v_daily_total || 
                    ', exceeding daily ceiling of ₹' || v_daily_limit
                );
            END IF;
        END LOOP;
    END AFTER STATEMENT;

END TRG_COMPOUND_DAILY_LIMIT;
/

-- =====================================================================
-- SECTION 3: AUTOMATED AUDIT TRAIL TRIGGER
-- =====================================================================
CREATE OR REPLACE TRIGGER TRG_ACCOUNT_AUDIT
AFTER UPDATE OF balance, status ON ACCOUNTS
FOR EACH ROW
DECLARE
    v_action VARCHAR2(35);
BEGIN
    IF :OLD.balance <> :NEW.balance THEN
        IF :NEW.balance > :OLD.balance THEN
            v_action := 'CREDIT_UPDATE';
        ELSE
            v_action := 'DEBIT_UPDATE';
        END IF;
    ELSIF :OLD.status <> :NEW.status THEN
        v_action := 'STATUS_CHANGED_TO_' || :NEW.status;
    ELSE
        v_action := 'METADATA_MODIFIED';
    END IF;

    INSERT INTO AUDIT_LOGS (
        log_id,
        account_no,
        action_type,
        old_balance,
        new_balance,
        changed_by,
        changed_at
    ) VALUES (
        SEQ_LOG_ID.NEXTVAL,
        :NEW.account_no,
        v_action,
        :OLD.balance,
        :NEW.balance,
        USER,
        CURRENT_TIMESTAMP
    );
END;
/

-- =====================================================================
-- SECTION 4: SAFETY TRIGGER PREVENTING DATA CORRUPTION
-- =====================================================================
CREATE OR REPLACE TRIGGER TRG_PREVENT_DELETE_ACTIVE
BEFORE DELETE ON ACCOUNTS
FOR EACH ROW
BEGIN
    IF :OLD.balance > 0 THEN
        RAISE_APPLICATION_ERROR(
            -20001, 
            'Cannot delete Account No: ' || :OLD.account_no || 
            '. Account still holds an active balance of ₹' || :OLD.balance || 
            '. Settle balance to ₹0.00 before deletion.'
        );
    END IF;
END;
/
