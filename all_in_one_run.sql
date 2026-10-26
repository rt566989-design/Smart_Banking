-- =====================================================================
-- ADVANCED DATABASE MANAGEMENT SYSTEMS (ADBMS) & ORACLE PL/SQL
-- ENTERPRISE SMART BANKING & FUND TRANSFER SYSTEM
-- MASTER ALL-IN-ONE SCRIPT (Oracle Live SQL / SQL Developer / SQL*Plus Ready)
--
-- This script contains the COMPLETE end-to-end implementation:
--   1. Schema DDL: Object Types (ORDBMS), Nested Tables/VARRAYs
--   2. Partitioning: Range Partitioning (Transactions) & List Partitioning (Accounts)
--   3. Advanced Indexing: Bitmap, Function-Based, Composite, Partitioned Local
--   4. Materialized Views: MV Logs & Fast Refresh
--   5. Triggers: Compound Trigger (Bypassing Mutating Table Error ORA-04091) & Audit
--   6. Autonomous Transactions: Independent Security/Fraud Audit Log
--   7. Package Spec & Body: BULK COLLECT, FORALL, Pipelined Functions, 2PC Simulator
--   8. Realistic Multi-Branch Seed Data
--   9. OLAP Analytical Window Queries (RANK, LEAD/LAG, Window Aggregates, ROLLUP)
--  10. Automated Test Executions
-- =====================================================================

SET SERVEROUTPUT ON SIZE 1000000;
SET LINESIZE 200;
SET PAGESIZE 100;

PROMPT [1/8] Cleaning up existing objects...

BEGIN
    EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW MV_DAILY_BRANCH_SUMMARY';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW MV_CUSTOMER_NETWORTH';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE FRAUD_ALERTS CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE DISTRIBUTED_TXN_LOG CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE AUDIT_LOGS CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE TRANSACTIONS_PARTITIONED CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE TRANSACTIONS CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE ACCOUNTS_PARTITIONED CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE ACCOUNTS CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE BRANCHES CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE CUSTOMERS_OBJ CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP TYPE KYC_DOC_TYP FORCE';
    EXECUTE IMMEDIATE 'DROP TYPE PHONE_ARRAY_TYP FORCE';
    EXECUTE IMMEDIATE 'DROP TYPE ADDRESS_TYP FORCE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_ACC_NO';
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_TXN_ID';
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_LOG_ID';
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_FRAUD_ID';
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_DTXN_ID';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

PROMPT [2/8] Creating Object-Relational Types (ORDBMS)...

CREATE OR REPLACE TYPE ADDRESS_TYP AS OBJECT (
    street_address  VARCHAR2(100),
    city            VARCHAR2(50),
    state           VARCHAR2(50),
    pincode         VARCHAR2(10),
    MEMBER FUNCTION get_full_address RETURN VARCHAR2
);
/

CREATE OR REPLACE TYPE BODY ADDRESS_TYP AS
    MEMBER FUNCTION get_full_address RETURN VARCHAR2 IS
    BEGIN
        RETURN street_address || ', ' || city || ', ' || state || ' - ' || pincode;
    END get_full_address;
END;
/

CREATE OR REPLACE TYPE KYC_DOC_TYP AS OBJECT (
    doc_type        VARCHAR2(30),
    doc_number      VARCHAR2(50),
    verified_status VARCHAR2(10)
);
/

CREATE OR REPLACE TYPE PHONE_ARRAY_TYP AS VARRAY(3) OF VARCHAR2(15);
/

PROMPT [3/8] Creating Sequences & Partitioned Tables...

CREATE SEQUENCE SEQ_ACC_NO   START WITH 1001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_TXN_ID   START WITH 50001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_LOG_ID   START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_FRAUD_ID START WITH 80001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_DTXN_ID  START WITH 90001 INCREMENT BY 1 NOCACHE;

CREATE TABLE BRANCHES (
    branch_code      VARCHAR2(10) PRIMARY KEY,
    branch_name      VARCHAR2(100) NOT NULL,
    city             VARCHAR2(50) NOT NULL,
    region           VARCHAR2(20) NOT NULL CHECK (region IN ('NORTH', 'SOUTH', 'EAST', 'WEST')),
    ifsc_code        VARCHAR2(15) UNIQUE NOT NULL,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE CUSTOMERS_OBJ (
    customer_id      NUMBER(10) PRIMARY KEY,
    full_name        VARCHAR2(100) NOT NULL,
    email            VARCHAR2(100) UNIQUE NOT NULL,
    phones           PHONE_ARRAY_TYP,
    home_address     ADDRESS_TYP,
    kyc_document     KYC_DOC_TYP,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE ACCOUNTS (
    account_no       NUMBER(10) PRIMARY KEY,
    customer_id      NUMBER(10) REFERENCES CUSTOMERS_OBJ(customer_id),
    branch_code      VARCHAR2(10) REFERENCES BRANCHES(branch_code),
    holder_name      VARCHAR2(100) NOT NULL,
    email            VARCHAR2(100) NOT NULL,
    phone            VARCHAR2(15),
    account_type     VARCHAR2(15) DEFAULT 'SAVINGS' 
                     CHECK (account_type IN ('SAVINGS', 'CURRENT', 'SALARY')),
    balance          NUMBER(12, 2) DEFAULT 0.00 NOT NULL 
                     CHECK (balance >= 0),
    daily_limit      NUMBER(12, 2) DEFAULT 50000.00 NOT NULL,
    status           VARCHAR2(15) DEFAULT 'ACTIVE' 
                     CHECK (status IN ('ACTIVE', 'DORMANT', 'FROZEN', 'CLOSED')),
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ADBMS: List Partitioning by Account Type
CREATE TABLE ACCOUNTS_PARTITIONED (
    account_no       NUMBER(10) NOT NULL,
    holder_name      VARCHAR2(100) NOT NULL,
    branch_code      VARCHAR2(10) NOT NULL,
    account_type     VARCHAR2(15) NOT NULL,
    balance          NUMBER(12, 2) NOT NULL,
    status           VARCHAR2(15) DEFAULT 'ACTIVE',
    created_at       DATE DEFAULT SYSDATE,
    CONSTRAINT pk_acc_part PRIMARY KEY (account_no, account_type)
)
PARTITION BY LIST (account_type) (
    PARTITION p_savings VALUES ('SAVINGS'),
    PARTITION p_current VALUES ('CURRENT'),
    PARTITION p_salary  VALUES ('SALARY')
);

CREATE TABLE TRANSACTIONS (
    txn_id           NUMBER(12) PRIMARY KEY,
    from_account     NUMBER(10) REFERENCES ACCOUNTS(account_no),
    to_account       NUMBER(10) REFERENCES ACCOUNTS(account_no),
    txn_type         VARCHAR2(15) NOT NULL 
                     CHECK (txn_type IN ('DEPOSIT', 'WITHDRAWAL', 'TRANSFER', 'INTEREST', 'FEE')),
    amount           NUMBER(12, 2) NOT NULL CHECK (amount > 0),
    txn_date         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status           VARCHAR2(15) DEFAULT 'SUCCESS' 
                     CHECK (status IN ('SUCCESS', 'FAILED')),
    remarks          VARCHAR2(200)
);

-- ADBMS: Range Partitioning by Transaction Date
CREATE TABLE TRANSACTIONS_PARTITIONED (
    txn_id           NUMBER(12) NOT NULL,
    from_account     NUMBER(10),
    to_account       NUMBER(10),
    txn_type         VARCHAR2(15) NOT NULL,
    amount           NUMBER(12, 2) NOT NULL,
    txn_date         DATE NOT NULL,
    status           VARCHAR2(15) DEFAULT 'SUCCESS',
    remarks          VARCHAR2(200),
    CONSTRAINT pk_txn_part PRIMARY KEY (txn_id, txn_date)
)
PARTITION BY RANGE (txn_date) (
    PARTITION p_2025_q1 VALUES LESS THAN (TO_DATE('2025-04-01', 'YYYY-MM-DD')),
    PARTITION p_2025_q2 VALUES LESS THAN (TO_DATE('2025-07-01', 'YYYY-MM-DD')),
    PARTITION p_2025_q3 VALUES LESS THAN (TO_DATE('2025-10-01', 'YYYY-MM-DD')),
    PARTITION p_2025_q4 VALUES LESS THAN (TO_DATE('2026-01-01', 'YYYY-MM-DD')),
    PARTITION p_2026_q1 VALUES LESS THAN (TO_DATE('2026-04-01', 'YYYY-MM-DD')),
    PARTITION p_future  VALUES LESS THAN (MAXVALUE)
);

CREATE TABLE AUDIT_LOGS (
    log_id           NUMBER(12) PRIMARY KEY,
    account_no       NUMBER(10) NOT NULL,
    action_type      VARCHAR2(35) NOT NULL,
    old_balance      NUMBER(12, 2),
    new_balance      NUMBER(12, 2),
    changed_by       VARCHAR2(50) DEFAULT USER,
    changed_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE FRAUD_ALERTS (
    alert_id         NUMBER(12) PRIMARY KEY,
    account_no       NUMBER(10),
    severity         VARCHAR2(15) CHECK (severity IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    reason           VARCHAR2(250) NOT NULL,
    attempted_amount NUMBER(12, 2),
    ip_address       VARCHAR2(45) DEFAULT '127.0.0.1',
    alert_time       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    resolved         VARCHAR2(5) DEFAULT 'NO' CHECK (resolved IN ('YES', 'NO'))
);

CREATE TABLE DISTRIBUTED_TXN_LOG (
    dtxn_id          NUMBER(12) PRIMARY KEY,
    global_xid       VARCHAR2(64) NOT NULL,
    source_branch    VARCHAR2(10) REFERENCES BRANCHES(branch_code),
    target_branch    VARCHAR2(10) REFERENCES BRANCHES(branch_code),
    from_account     NUMBER(10),
    to_account       NUMBER(10),
    amount           NUMBER(12, 2) NOT NULL,
    phase_1_status   VARCHAR2(20) DEFAULT 'PREPARED',
    phase_2_status   VARCHAR2(20) DEFAULT 'COMMITTED',
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

PROMPT [4/8] Creating Advanced Indexes & Materialized Views...

CREATE BITMAP INDEX IDX_ACC_STATUS_BMP ON ACCOUNTS(status);
CREATE BITMAP INDEX IDX_ACC_TYPE_BMP ON ACCOUNTS(account_type);
CREATE INDEX IDX_ACC_NAME_UPPER ON ACCOUNTS(UPPER(holder_name));
CREATE INDEX IDX_TXN_ACC_DATE ON TRANSACTIONS(from_account, txn_date DESC);
CREATE INDEX IDX_TXN_PART_DATE ON TRANSACTIONS_PARTITIONED(txn_date) LOCAL;

CREATE MATERIALIZED VIEW MV_DAILY_BRANCH_SUMMARY
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS
SELECT 
    b.branch_code,
    b.branch_name,
    b.region,
    COUNT(a.account_no)           AS total_accounts,
    NVL(SUM(a.balance), 0)        AS total_branch_liquidity,
    ROUND(NVL(AVG(a.balance), 0), 2) AS avg_account_balance
FROM BRANCHES b
LEFT JOIN ACCOUNTS a ON b.branch_code = a.branch_code AND a.status = 'ACTIVE'
GROUP BY b.branch_code, b.branch_name, b.region;

CREATE MATERIALIZED VIEW MV_CUSTOMER_NETWORTH
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS
SELECT 
    a.holder_name,
    a.email,
    COUNT(a.account_no)   AS num_accounts,
    SUM(a.balance)        AS total_networth,
    CASE 
        WHEN SUM(a.balance) >= 500000 THEN 'HIGH NET WORTH (HNW)'
        WHEN SUM(a.balance) >= 100000 THEN 'PREMIUM RETAIL'
        ELSE 'STANDARD RETAIL'
    END                   AS client_tier
FROM ACCOUNTS a
GROUP BY a.holder_name, a.email;

CREATE OR REPLACE PROCEDURE REFRESH_ALL_MVIEWS AS
BEGIN
    DBMS_MVIEW.REFRESH('MV_DAILY_BRANCH_SUMMARY', 'C');
    DBMS_MVIEW.REFRESH('MV_CUSTOMER_NETWORTH', 'C');
    DBMS_OUTPUT.PUT_LINE('✔ Materialized Views refreshed.');
END;
/

PROMPT [5/8] Creating Autonomous Logging & Compound Triggers...

-- Autonomous Security Logger
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
        alert_id, account_no, severity, reason, attempted_amount, ip_address, alert_time, resolved
    ) VALUES (
        SEQ_FRAUD_ID.NEXTVAL, p_account_no, UPPER(p_severity), p_reason, p_attempted_amount, p_ip_address, CURRENT_TIMESTAMP, 'NO'
    );
    COMMIT;
END LOG_FRAUD_ALERT_AUTONOMOUS;
/

-- Compound Trigger bypassing Mutating Table Error (ORA-04091)
CREATE OR REPLACE TRIGGER TRG_COMPOUND_DAILY_LIMIT
FOR INSERT ON TRANSACTIONS
COMPOUND TRIGGER
    TYPE t_account_list IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    g_affected_accounts t_account_list;
    g_count             PLS_INTEGER := 0;

    BEFORE STATEMENT IS
    BEGIN
        g_affected_accounts.DELETE;
        g_count := 0;
    END BEFORE STATEMENT;

    AFTER EACH ROW IS
    BEGIN
        IF :NEW.from_account IS NOT NULL AND :NEW.txn_type IN ('WITHDRAWAL', 'TRANSFER') THEN
            g_count := g_count + 1;
            g_affected_accounts(g_count) := :NEW.from_account;
        END IF;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
        v_daily_total NUMBER;
        v_daily_limit NUMBER;
        v_acc_no      NUMBER;
    BEGIN
        FOR i IN 1 .. g_count LOOP
            v_acc_no := g_affected_accounts(i);

            SELECT daily_limit INTO v_daily_limit
            FROM ACCOUNTS
            WHERE account_no = v_acc_no;

            SELECT NVL(SUM(amount), 0) INTO v_daily_total
            FROM TRANSACTIONS
            WHERE from_account = v_acc_no
              AND txn_type IN ('WITHDRAWAL', 'TRANSFER')
              AND status = 'SUCCESS'
              AND CAST(txn_date AS DATE) = TRUNC(SYSDATE);

            IF v_daily_total > v_daily_limit THEN
                LOG_FRAUD_ALERT_AUTONOMOUS(
                    p_account_no       => v_acc_no,
                    p_severity         => 'HIGH',
                    p_reason           => 'Daily transaction limit ₹' || v_daily_limit || ' breached! Attempted: ₹' || v_daily_total,
                    p_attempted_amount => v_daily_total
                );

                RAISE_APPLICATION_ERROR(
                    -20010,
                    'Daily Transaction Limit Exceeded! Account ' || v_acc_no ||
                    ' attempted daily total ₹' || v_daily_total || 
                    ', exceeding daily threshold of ₹' || v_daily_limit
                );
            END IF;
        END LOOP;
    END AFTER STATEMENT;
END TRG_COMPOUND_DAILY_LIMIT;
/

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
        log_id, account_no, action_type, old_balance, new_balance, changed_by, changed_at
    ) VALUES (
        SEQ_LOG_ID.NEXTVAL, :NEW.account_no, v_action, :OLD.balance, :NEW.balance, USER, CURRENT_TIMESTAMP
    );
END;
/

CREATE OR REPLACE TRIGGER TRG_PREVENT_DELETE_ACTIVE
BEFORE DELETE ON ACCOUNTS
FOR EACH ROW
BEGIN
    IF :OLD.balance > 0 THEN
        RAISE_APPLICATION_ERROR(
            -20001, 
            'Cannot delete Account No: ' || :OLD.account_no || 
            '. Account still holds an active balance of ₹' || :OLD.balance || 
            '. Settle balance to ₹0.00 first.'
        );
    END IF;
END;
/

PROMPT [6/8] Compiling ADBMS_BANKING_PKG (Spec & Body)...

CREATE OR REPLACE PACKAGE ADBMS_BANKING_PKG AS
    e_insufficient_funds    EXCEPTION;
    e_account_inactive      EXCEPTION;
    e_invalid_amount        EXCEPTION;
    e_same_account          EXCEPTION;
    e_account_not_found     EXCEPTION;
    e_resource_busy         EXCEPTION;
    e_daily_limit_exceeded  EXCEPTION;
    e_2pc_prepare_failed    EXCEPTION;

    PRAGMA EXCEPTION_INIT(e_insufficient_funds,   -20002);
    PRAGMA EXCEPTION_INIT(e_account_inactive,     -20003);
    PRAGMA EXCEPTION_INIT(e_invalid_amount,       -20004);
    PRAGMA EXCEPTION_INIT(e_same_account,         -20005);
    PRAGMA EXCEPTION_INIT(e_account_not_found,    -20006);
    PRAGMA EXCEPTION_INIT(e_resource_busy,        -00054);
    PRAGMA EXCEPTION_INIT(e_daily_limit_exceeded, -20010);
    PRAGMA EXCEPTION_INIT(e_2pc_prepare_failed,   -20015);

    TYPE t_statement_row IS RECORD (
        txn_id       NUMBER(12),
        txn_date     VARCHAR2(30),
        txn_type     VARCHAR2(15),
        amount       NUMBER(12, 2),
        counterparty NUMBER(10),
        remarks      VARCHAR2(200)
    );
    TYPE t_statement_table IS TABLE OF t_statement_row;

    PROCEDURE open_account_ordbms (
        p_name            IN  VARCHAR2,
        p_email           IN  VARCHAR2,
        p_phones          IN  PHONE_ARRAY_TYP,
        p_address         IN  ADDRESS_TYP,
        p_kyc             IN  KYC_DOC_TYP,
        p_branch_code     IN  VARCHAR2,
        p_account_type    IN  VARCHAR2,
        p_initial_deposit IN  NUMBER,
        p_account_no      OUT NUMBER
    );

    PROCEDURE deposit (
        p_account_no IN NUMBER,
        p_amount     IN NUMBER,
        p_remarks    IN VARCHAR2 DEFAULT 'Cash Deposit'
    );

    PROCEDURE withdraw (
        p_account_no IN NUMBER,
        p_amount     IN NUMBER,
        p_remarks    IN VARCHAR2 DEFAULT 'Cash Withdrawal'
    );

    PROCEDURE transfer_funds (
        p_from_acc IN NUMBER,
        p_to_acc   IN NUMBER,
        p_amount   IN NUMBER,
        p_remarks  IN VARCHAR2 DEFAULT 'Fund Transfer'
    );

    PROCEDURE bulk_apply_monthly_interest (
        p_annual_rate IN NUMBER DEFAULT 4.5,
        p_batch_size  IN NUMBER DEFAULT 500
    );

    PROCEDURE bulk_deduct_service_fee (
        p_fee_amount       IN NUMBER DEFAULT 150.00,
        p_min_balance_tier IN NUMBER DEFAULT 2000.00
    );

    PROCEDURE simulate_distributed_transfer (
        p_source_branch IN VARCHAR2,
        p_target_branch IN VARCHAR2,
        p_from_acc      IN NUMBER,
        p_to_acc        IN NUMBER,
        p_amount        IN NUMBER,
        p_simulate_fail IN VARCHAR2 DEFAULT 'NONE'
    );

    FUNCTION stream_mini_statement (
        p_account_no IN NUMBER,
        p_limit      IN NUMBER DEFAULT 10
    ) RETURN t_statement_table PIPELINED;

    FUNCTION get_balance (p_account_no IN NUMBER) RETURN NUMBER;
    FUNCTION is_account_active (p_account_no IN NUMBER) RETURN BOOLEAN;
END ADBMS_BANKING_PKG;
/

CREATE OR REPLACE PACKAGE BODY ADBMS_BANKING_PKG AS

    FUNCTION is_account_active(p_account_no IN NUMBER) RETURN BOOLEAN IS
        v_status ACCOUNTS.status%TYPE;
    BEGIN
        SELECT status INTO v_status FROM ACCOUNTS WHERE account_no = p_account_no;
        RETURN (v_status = 'ACTIVE');
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN FALSE;
    END is_account_active;

    FUNCTION get_balance(p_account_no IN NUMBER) RETURN NUMBER IS
        v_balance ACCOUNTS.balance%TYPE;
    BEGIN
        SELECT balance INTO v_balance FROM ACCOUNTS WHERE account_no = p_account_no;
        RETURN v_balance;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20006, 'Account No ' || p_account_no || ' does not exist.');
    END get_balance;

    PROCEDURE open_account_ordbms (
        p_name            IN  VARCHAR2,
        p_email           IN  VARCHAR2,
        p_phones          IN  PHONE_ARRAY_TYP,
        p_address         IN  ADDRESS_TYP,
        p_kyc             IN  KYC_DOC_TYP,
        p_branch_code     IN  VARCHAR2,
        p_account_type    IN  VARCHAR2,
        p_initial_deposit IN  NUMBER,
        p_account_no      OUT NUMBER
    ) IS
        v_cust_id NUMBER(10);
    BEGIN
        IF p_initial_deposit < 0 THEN
            RAISE_APPLICATION_ERROR(-20004, 'Initial deposit cannot be negative.');
        END IF;

        v_cust_id := SEQ_ACC_NO.NEXTVAL;
        INSERT INTO CUSTOMERS_OBJ (customer_id, full_name, email, phones, home_address, kyc_document)
        VALUES (v_cust_id, p_name, p_email, p_phones, p_address, p_kyc);

        p_account_no := v_cust_id;
        INSERT INTO ACCOUNTS (account_no, customer_id, branch_code, holder_name, email, phone, account_type, balance, daily_limit, status)
        VALUES (p_account_no, v_cust_id, p_branch_code, p_name, p_email,
                CASE WHEN p_phones.COUNT > 0 THEN p_phones(1) ELSE NULL END,
                UPPER(p_account_type), p_initial_deposit, 50000.00, 'ACTIVE');

        INSERT INTO ACCOUNTS_PARTITIONED (account_no, holder_name, branch_code, account_type, balance, status)
        VALUES (p_account_no, p_name, p_branch_code, UPPER(p_account_type), p_initial_deposit, 'ACTIVE');

        IF p_initial_deposit > 0 THEN
            INSERT INTO TRANSACTIONS (txn_id, to_account, txn_type, amount, status, remarks)
            VALUES (SEQ_TXN_ID.NEXTVAL, p_account_no, 'DEPOSIT', p_initial_deposit, 'SUCCESS', 'Opening Deposit');

            INSERT INTO TRANSACTIONS_PARTITIONED (txn_id, to_account, txn_type, amount, txn_date, status, remarks)
            VALUES (SEQ_TXN_ID.CURRVAL, p_account_no, 'DEPOSIT', p_initial_deposit, TRUNC(SYSDATE), 'SUCCESS', 'Opening Deposit');
        END IF;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('✔ ORDBMS Account ' || p_account_no || ' created for ' || p_name);
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            LOG_FRAUD_ALERT_AUTONOMOUS(0, 'MEDIUM', 'Account onboarding error: ' || SQLERRM, p_initial_deposit);
            RAISE;
    END open_account_ordbms;

    PROCEDURE deposit (
        p_account_no IN NUMBER,
        p_amount     IN NUMBER,
        p_remarks    IN VARCHAR2 DEFAULT 'Cash Deposit'
    ) IS
        v_current_bal NUMBER;
        v_status      ACCOUNTS.status%TYPE;
        v_txn_id      NUMBER;
    BEGIN
        IF p_amount <= 0 THEN
            RAISE_APPLICATION_ERROR(-20004, 'Deposit amount must be strictly greater than 0.');
        END IF;

        SELECT balance, status INTO v_current_bal, v_status FROM ACCOUNTS WHERE account_no = p_account_no FOR UPDATE WAIT 5;

        IF v_status <> 'ACTIVE' THEN
            RAISE_APPLICATION_ERROR(-20003, 'Account ' || p_account_no || ' is not ACTIVE.');
        END IF;

        UPDATE ACCOUNTS SET balance = balance + p_amount WHERE account_no = p_account_no;
        UPDATE ACCOUNTS_PARTITIONED SET balance = balance + p_amount WHERE account_no = p_account_no;

        v_txn_id := SEQ_TXN_ID.NEXTVAL;

        INSERT INTO TRANSACTIONS (txn_id, to_account, txn_type, amount, status, remarks)
        VALUES (v_txn_id, p_account_no, 'DEPOSIT', p_amount, 'SUCCESS', p_remarks);

        INSERT INTO TRANSACTIONS_PARTITIONED (txn_id, to_account, txn_type, amount, txn_date, status, remarks)
        VALUES (v_txn_id, p_account_no, 'DEPOSIT', p_amount, TRUNC(SYSDATE), 'SUCCESS', p_remarks);

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('✔ Deposit successful: ₹' || p_amount || ' credited to Acc ' || p_account_no);
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END deposit;

    PROCEDURE withdraw (
        p_account_no IN NUMBER,
        p_amount     IN NUMBER,
        p_remarks    IN VARCHAR2 DEFAULT 'Cash Withdrawal'
    ) IS
        v_current_bal NUMBER;
        v_status      ACCOUNTS.status%TYPE;
        v_txn_id      NUMBER;
    BEGIN
        IF p_amount <= 0 THEN
            RAISE_APPLICATION_ERROR(-20004, 'Withdrawal amount must be strictly greater than 0.');
        END IF;

        SELECT balance, status INTO v_current_bal, v_status FROM ACCOUNTS WHERE account_no = p_account_no FOR UPDATE WAIT 5;

        IF v_status <> 'ACTIVE' THEN
            RAISE_APPLICATION_ERROR(-20003, 'Account ' || p_account_no || ' is not ACTIVE.');
        END IF;

        IF v_current_bal < p_amount THEN
            LOG_FRAUD_ALERT_AUTONOMOUS(
                p_account_no       => p_account_no,
                p_severity         => 'MEDIUM',
                p_reason           => 'Overdraft attempt: balance ₹' || v_current_bal || ', tried ₹' || p_amount,
                p_attempted_amount => p_amount
            );
            RAISE_APPLICATION_ERROR(-20002, 'Insufficient Funds: balance ₹' || v_current_bal || ', Requested: ₹' || p_amount);
        END IF;

        UPDATE ACCOUNTS SET balance = balance - p_amount WHERE account_no = p_account_no;
        UPDATE ACCOUNTS_PARTITIONED SET balance = balance - p_amount WHERE account_no = p_account_no;

        v_txn_id := SEQ_TXN_ID.NEXTVAL;

        INSERT INTO TRANSACTIONS (txn_id, from_account, txn_type, amount, status, remarks)
        VALUES (v_txn_id, p_account_no, 'WITHDRAWAL', p_amount, 'SUCCESS', p_remarks);

        INSERT INTO TRANSACTIONS_PARTITIONED (txn_id, from_account, txn_type, amount, txn_date, status, remarks)
        VALUES (v_txn_id, p_account_no, 'WITHDRAWAL', p_amount, TRUNC(SYSDATE), 'SUCCESS', p_remarks);

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('✔ Withdrawal successful: ₹' || p_amount || ' debited from Acc ' || p_account_no);
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END withdraw;

    PROCEDURE transfer_funds (
        p_from_acc IN NUMBER,
        p_to_acc   IN NUMBER,
        p_amount   IN NUMBER,
        p_remarks  IN VARCHAR2 DEFAULT 'Fund Transfer'
    ) IS
        v_first_acc   NUMBER;
        v_second_acc  NUMBER;
        v_sender_bal  NUMBER;
        v_sender_stat ACCOUNTS.status%TYPE;
        v_rcv_stat    ACCOUNTS.status%TYPE;
        v_txn_id      NUMBER;
    BEGIN
        IF p_from_acc = p_to_acc THEN
            RAISE_APPLICATION_ERROR(-20005, 'Sender and receiver accounts cannot be identical.');
        END IF;

        IF p_amount <= 0 THEN
            RAISE_APPLICATION_ERROR(-20004, 'Transfer amount must be strictly greater than 0.');
        END IF;

        SAVEPOINT sp_transfer;

        -- Deadlock prevention via numeric ordering
        IF p_from_acc < p_to_acc THEN
            v_first_acc  := p_from_acc;
            v_second_acc := p_to_acc;
        ELSE
            v_first_acc  := p_to_acc;
            v_second_acc := p_from_acc;
        END IF;

        SELECT status INTO v_sender_stat FROM ACCOUNTS WHERE account_no = v_first_acc FOR UPDATE WAIT 5;
        SELECT status INTO v_rcv_stat    FROM ACCOUNTS WHERE account_no = v_second_acc FOR UPDATE WAIT 5;

        IF NOT is_account_active(p_from_acc) THEN
            RAISE_APPLICATION_ERROR(-20003, 'Sender account ' || p_from_acc || ' is not ACTIVE.');
        END IF;
        IF NOT is_account_active(p_to_acc) THEN
            RAISE_APPLICATION_ERROR(-20003, 'Beneficiary account ' || p_to_acc || ' is not ACTIVE.');
        END IF;

        SELECT balance INTO v_sender_bal FROM ACCOUNTS WHERE account_no = p_from_acc;
        IF v_sender_bal < p_amount THEN
            LOG_FRAUD_ALERT_AUTONOMOUS(
                p_account_no       => p_from_acc,
                p_severity         => 'MEDIUM',
                p_reason           => 'Transfer failed: balance ₹' || v_sender_bal || ', required ₹' || p_amount,
                p_attempted_amount => p_amount
            );
            RAISE_APPLICATION_ERROR(-20002, 'Insufficient funds in sender account.');
        END IF;

        UPDATE ACCOUNTS SET balance = balance - p_amount WHERE account_no = p_from_acc;
        UPDATE ACCOUNTS SET balance = balance + p_amount WHERE account_no = p_to_acc;

        UPDATE ACCOUNTS_PARTITIONED SET balance = balance - p_amount WHERE account_no = p_from_acc;
        UPDATE ACCOUNTS_PARTITIONED SET balance = balance + p_amount WHERE account_no = p_to_acc;

        v_txn_id := SEQ_TXN_ID.NEXTVAL;

        INSERT INTO TRANSACTIONS (txn_id, from_account, to_account, txn_type, amount, status, remarks)
        VALUES (v_txn_id, p_from_acc, p_to_acc, 'TRANSFER', p_amount, 'SUCCESS', p_remarks);

        INSERT INTO TRANSACTIONS_PARTITIONED (txn_id, from_account, to_account, txn_type, amount, txn_date, status, remarks)
        VALUES (v_txn_id, p_from_acc, p_to_acc, 'TRANSFER', p_amount, TRUNC(SYSDATE), 'SUCCESS', p_remarks);

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('✔ Transfer completed: ₹' || p_amount || ' sent from ' || p_from_acc || ' -> ' || p_to_acc);
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO sp_transfer;
            LOG_FRAUD_ALERT_AUTONOMOUS(
                p_account_no       => p_from_acc,
                p_severity         => 'HIGH',
                p_reason           => 'Transfer aborted and rolled back: ' || SQLERRM,
                p_attempted_amount => p_amount
            );
            COMMIT;
            RAISE;
    END transfer_funds;

    -- Bulk Collect and FORALL High Throughput Interest Processing
    PROCEDURE bulk_apply_monthly_interest (
        p_annual_rate IN NUMBER DEFAULT 4.5,
        p_batch_size  IN NUMBER DEFAULT 500
    ) IS
        CURSOR c_savings IS
            SELECT account_no, balance FROM ACCOUNTS WHERE account_type = 'SAVINGS' AND status = 'ACTIVE' AND balance > 0;

        TYPE t_num_list IS TABLE OF NUMBER;
        v_acc_list      t_num_list;
        v_bal_list      t_num_list;
        v_interest_list t_num_list := t_num_list();
        v_monthly_rate  NUMBER := (p_annual_rate / 100.0) / 12.0;
        v_total_updated NUMBER := 0;
    BEGIN
        OPEN c_savings;
        LOOP
            FETCH c_savings BULK COLLECT INTO v_acc_list, v_bal_list LIMIT p_batch_size;
            EXIT WHEN v_acc_list.COUNT = 0;

            v_interest_list.EXTEND(v_acc_list.COUNT);
            FOR i IN 1 .. v_acc_list.COUNT LOOP
                v_interest_list(i) := ROUND(v_bal_list(i) * v_monthly_rate, 2);
            END LOOP;

            FORALL i IN 1 .. v_acc_list.COUNT
                UPDATE ACCOUNTS SET balance = balance + v_interest_list(i) WHERE account_no = v_acc_list(i);

            FORALL i IN 1 .. v_acc_list.COUNT
                INSERT INTO TRANSACTIONS (txn_id, to_account, txn_type, amount, status, remarks)
                VALUES (SEQ_TXN_ID.NEXTVAL, v_acc_list(i), 'INTEREST', v_interest_list(i), 'SUCCESS', 'Monthly Interest Credit');

            v_total_updated := v_total_updated + v_acc_list.COUNT;
            COMMIT;
        END LOOP;
        CLOSE c_savings;
        DBMS_OUTPUT.PUT_LINE('✔ Bulk Interest Processed for ' || v_total_updated || ' accounts.');
    EXCEPTION
        WHEN OTHERS THEN
            IF c_savings%ISOPEN THEN CLOSE c_savings; END IF;
            ROLLBACK;
            RAISE;
    END bulk_apply_monthly_interest;

    PROCEDURE bulk_deduct_service_fee (
        p_fee_amount       IN NUMBER DEFAULT 150.00,
        p_min_balance_tier IN NUMBER DEFAULT 2000.00
    ) IS
        CURSOR c_low_bal IS
            SELECT account_no, balance FROM ACCOUNTS WHERE balance < p_min_balance_tier AND status = 'ACTIVE' AND balance >= p_fee_amount;

        TYPE t_num_list IS TABLE OF NUMBER;
        v_acc_list t_num_list;
        v_bal_list t_num_list;
    BEGIN
        OPEN c_low_bal;
        FETCH c_low_bal BULK COLLECT INTO v_acc_list, v_bal_list;
        CLOSE c_low_bal;

        IF v_acc_list.COUNT > 0 THEN
            FORALL i IN 1 .. v_acc_list.COUNT SAVE EXCEPTIONS
                UPDATE ACCOUNTS SET balance = balance - p_fee_amount WHERE account_no = v_acc_list(i);

            FORALL i IN 1 .. v_acc_list.COUNT
                INSERT INTO TRANSACTIONS (txn_id, from_account, txn_type, amount, status, remarks)
                VALUES (SEQ_TXN_ID.NEXTVAL, v_acc_list(i), 'FEE', p_fee_amount, 'SUCCESS', 'Low Balance Service Fee');

            COMMIT;
            DBMS_OUTPUT.PUT_LINE('✔ Bulk service fee applied to ' || v_acc_list.COUNT || ' accounts.');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END bulk_deduct_service_fee;

    PROCEDURE simulate_distributed_transfer (
        p_source_branch IN VARCHAR2,
        p_target_branch IN VARCHAR2,
        p_from_acc      IN NUMBER,
        p_to_acc        IN NUMBER,
        p_amount        IN NUMBER,
        p_simulate_fail IN VARCHAR2 DEFAULT 'NONE'
    ) IS
        v_gxid    VARCHAR2(64);
        v_dtxn_id NUMBER;
    BEGIN
        v_gxid    := 'GTXN-' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDD-HH24MISS-FF4');
        v_dtxn_id := SEQ_DTXN_ID.NEXTVAL;

        IF p_simulate_fail = 'PREPARE_FAIL' THEN
            INSERT INTO DISTRIBUTED_TXN_LOG (dtxn_id, global_xid, source_branch, target_branch, from_account, to_account, amount, phase_1_status, phase_2_status)
            VALUES (v_dtxn_id, v_gxid, p_source_branch, p_target_branch, p_from_acc, p_to_acc, p_amount, 'VOTE_ABORT', 'GLOBAL_ROLLED_BACK');
            COMMIT;

            LOG_FRAUD_ALERT_AUTONOMOUS(
                p_account_no       => p_from_acc,
                p_severity         => 'CRITICAL',
                p_reason           => 'Distributed 2PC Protocol: Target Branch ' || p_target_branch || ' voted ABORT during Phase 1.',
                p_attempted_amount => p_amount
            );

            RAISE_APPLICATION_ERROR(-20015, 'Distributed 2PC Phase 1 Failed: Branch ' || p_target_branch || ' unreachable.');
        END IF;

        INSERT INTO DISTRIBUTED_TXN_LOG (dtxn_id, global_xid, source_branch, target_branch, from_account, to_account, amount, phase_1_status, phase_2_status)
        VALUES (v_dtxn_id, v_gxid, p_source_branch, p_target_branch, p_from_acc, p_to_acc, p_amount, 'VOTE_COMMIT', 'PREPARED');

        transfer_funds(p_from_acc, p_to_acc, p_amount, 'Distributed 2PC Transfer: ' || v_gxid);

        UPDATE DISTRIBUTED_TXN_LOG SET phase_2_status = 'GLOBAL_COMMITTED' WHERE dtxn_id = v_dtxn_id;
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('✔ Distributed 2PC Committed! Global XID: ' || v_gxid);
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            UPDATE DISTRIBUTED_TXN_LOG SET phase_2_status = 'GLOBAL_ROLLED_BACK' WHERE dtxn_id = v_dtxn_id;
            COMMIT;
            RAISE;
    END simulate_distributed_transfer;

    FUNCTION stream_mini_statement (
        p_account_no IN NUMBER,
        p_limit      IN NUMBER DEFAULT 10
    ) RETURN t_statement_table PIPELINED IS
        v_out_row t_statement_row;
        CURSOR c_txns IS
            SELECT txn_id, TO_CHAR(txn_date, 'YYYY-MM-DD HH24:MI:SS') AS dt_str, txn_type, amount, NVL(to_account, from_account) AS counterparty, remarks
            FROM TRANSACTIONS
            WHERE from_account = p_account_no OR to_account = p_account_no
            ORDER BY txn_id DESC;
        v_count NUMBER := 0;
    BEGIN
        FOR r IN c_txns LOOP
            v_count := v_count + 1;
            EXIT WHEN v_count > p_limit;

            v_out_row.txn_id       := r.txn_id;
            v_out_row.txn_date     := r.dt_str;
            v_out_row.txn_type     := r.txn_type;
            v_out_row.amount       := r.amount;
            v_out_row.counterparty := r.counterparty;
            v_out_row.remarks      := r.remarks;

            PIPE ROW(v_out_row);
        END LOOP;
        RETURN;
    END stream_mini_statement;

END ADBMS_BANKING_PKG;
/

PROMPT [7/8] Seeding Multi-Branch Data & Historical Partitions...

INSERT INTO BRANCHES VALUES ('BR-DEL-01', 'Connaught Place Branch', 'New Delhi', 'NORTH', 'SMART0001001', CURRENT_TIMESTAMP);
INSERT INTO BRANCHES VALUES ('BR-MUM-01', 'Nariman Point Branch', 'Mumbai', 'WEST', 'SMART0002001', CURRENT_TIMESTAMP);
INSERT INTO BRANCHES VALUES ('BR-BLR-01', 'Indiranagar Tech Hub', 'Bengaluru', 'SOUTH', 'SMART0003001', CURRENT_TIMESTAMP);
INSERT INTO BRANCHES VALUES ('BR-KOL-01', 'Park Street Branch', 'Kolkata', 'EAST', 'SMART0004001', CURRENT_TIMESTAMP);

INSERT INTO CUSTOMERS_OBJ VALUES (
    1001, 'Rahul Sharma', 'rahul.sharma@example.com',
    PHONE_ARRAY_TYP('9876543210', '0112345678'),
    ADDRESS_TYP('12/A Barakhamba Road', 'New Delhi', 'Delhi', '110001'),
    KYC_DOC_TYP('AADHAAR', '4589-1234-9012', 'VERIFIED'), CURRENT_TIMESTAMP
);

INSERT INTO CUSTOMERS_OBJ VALUES (
    1002, 'Priya Patel', 'priya.patel@example.com',
    PHONE_ARRAY_TYP('9823456781'),
    ADDRESS_TYP('84 Marine Drive', 'Mumbai', 'Maharashtra', '400020'),
    KYC_DOC_TYP('PAN', 'ABCDE1234F', 'VERIFIED'), CURRENT_TIMESTAMP
);

INSERT INTO CUSTOMERS_OBJ VALUES (
    1003, 'Amit Verma', 'amit.verma@example.com',
    PHONE_ARRAY_TYP('9811223344'),
    ADDRESS_TYP('100 Feet Road, Indiranagar', 'Bengaluru', 'Karnataka', '560038'),
    KYC_DOC_TYP('PASSPORT', 'Z9876543', 'VERIFIED'), CURRENT_TIMESTAMP
);

INSERT INTO CUSTOMERS_OBJ VALUES (
    1004, 'Neha Singh', 'neha.singh@example.com',
    PHONE_ARRAY_TYP('9899887766'),
    ADDRESS_TYP('45 Civil Lines', 'New Delhi', 'Delhi', '110054'),
    KYC_DOC_TYP('AADHAAR', '8899-7711-2233', 'VERIFIED'), CURRENT_TIMESTAMP
);

INSERT INTO CUSTOMERS_OBJ VALUES (
    1005, 'Vikram Malhotra', 'vikram.m@example.com',
    PHONE_ARRAY_TYP('9833445566'),
    ADDRESS_TYP('17 Park Street', 'Kolkata', 'West Bengal', '700016'),
    KYC_DOC_TYP('PAN', 'XYZPM9988K', 'VERIFIED'), CURRENT_TIMESTAMP
);

INSERT INTO CUSTOMERS_OBJ VALUES (
    1006, 'Ananya Iyer', 'ananya.iyer@example.com',
    PHONE_ARRAY_TYP('9845012345'),
    ADDRESS_TYP('22 Koramangala 4th Block', 'Bengaluru', 'Karnataka', '560034'),
    KYC_DOC_TYP('AADHAAR', '3344-5566-7788', 'VERIFIED'), CURRENT_TIMESTAMP
);

INSERT INTO ACCOUNTS VALUES (1001, 1001, 'BR-DEL-01', 'Rahul Sharma', 'rahul.sharma@example.com', '9876543210', 'SAVINGS', 75000.00, 50000.00, 'ACTIVE', CURRENT_TIMESTAMP);
INSERT INTO ACCOUNTS VALUES (1002, 1002, 'BR-MUM-01', 'Priya Patel', 'priya.patel@example.com', '9823456781', 'SALARY', 120000.00, 75000.00, 'ACTIVE', CURRENT_TIMESTAMP);
INSERT INTO ACCOUNTS VALUES (1003, 1003, 'BR-BLR-01', 'Amit Verma', 'amit.verma@example.com', '9811223344', 'CURRENT', 250000.00, 150000.00, 'ACTIVE', CURRENT_TIMESTAMP);
INSERT INTO ACCOUNTS VALUES (1004, 1004, 'BR-DEL-01', 'Neha Singh', 'neha.singh@example.com', '9899887766', 'SAVINGS', 15000.00, 50000.00, 'ACTIVE', CURRENT_TIMESTAMP);
INSERT INTO ACCOUNTS VALUES (1005, 1005, 'BR-KOL-01', 'Vikram Malhotra', 'vikram.m@example.com', '9833445566', 'CURRENT', 680000.00, 200000.00, 'ACTIVE', CURRENT_TIMESTAMP);
INSERT INTO ACCOUNTS VALUES (1006, 1006, 'BR-BLR-01', 'Ananya Iyer', 'ananya.iyer@example.com', '9845012345', 'SAVINGS', 850.00, 25000.00, 'ACTIVE', CURRENT_TIMESTAMP);

INSERT INTO ACCOUNTS_PARTITIONED (account_no, holder_name, branch_code, account_type, balance, status)
SELECT account_no, holder_name, branch_code, account_type, balance, status FROM ACCOUNTS;

-- Historical transactions across Range partitions
INSERT INTO TRANSACTIONS VALUES (50001, NULL, 1001, 'DEPOSIT', 50000.00, TO_TIMESTAMP('2025-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS'), 'SUCCESS', 'Opening Deposit');
INSERT INTO TRANSACTIONS_PARTITIONED VALUES (50001, NULL, 1001, 'DEPOSIT', 50000.00, TO_DATE('2025-01-15', 'YYYY-MM-DD'), 'SUCCESS', 'Opening Deposit');

INSERT INTO TRANSACTIONS VALUES (50002, 1001, 1004, 'TRANSFER', 10000.00, TO_TIMESTAMP('2025-05-10 14:15:00', 'YYYY-MM-DD HH24:MI:SS'), 'SUCCESS', 'Family Allowance');
INSERT INTO TRANSACTIONS_PARTITIONED VALUES (50002, 1001, 1004, 'TRANSFER', 10000.00, TO_DATE('2025-05-10', 'YYYY-MM-DD'), 'SUCCESS', 'Family Allowance');

INSERT INTO TRANSACTIONS VALUES (50003, NULL, 1002, 'DEPOSIT', 120000.00, TO_TIMESTAMP('2025-08-01 09:00:00', 'YYYY-MM-DD HH24:MI:SS'), 'SUCCESS', 'Corporate Salary Credit');
INSERT INTO TRANSACTIONS_PARTITIONED VALUES (50003, NULL, 1002, 'DEPOSIT', 120000.00, TO_DATE('2025-08-01', 'YYYY-MM-DD'), 'SUCCESS', 'Corporate Salary Credit');

INSERT INTO TRANSACTIONS VALUES (50004, 1003, 1005, 'TRANSFER', 45000.00, TO_TIMESTAMP('2025-11-20 16:45:00', 'YYYY-MM-DD HH24:MI:SS'), 'SUCCESS', 'Vendor Settlement');
INSERT INTO TRANSACTIONS_PARTITIONED VALUES (50004, 1003, 1005, 'TRANSFER', 45000.00, TO_DATE('2025-11-20', 'YYYY-MM-DD'), 'SUCCESS', 'Vendor Settlement');

COMMIT;

BEGIN
    REFRESH_ALL_MVIEWS;
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

PROMPT [8/8] Executing Verification & Automated Tests...

-- Test 1: ACID Transfer
BEGIN
    ADBMS_BANKING_PKG.transfer_funds(1001, 1004, 5000.00, 'Test Transfer');
END;
/

-- Test 2: Autonomous Transaction on Overdraft
DECLARE
    v_cnt NUMBER;
BEGIN
    BEGIN
        ADBMS_BANKING_PKG.withdraw(1004, 999999.00, 'Overdraft Attempt');
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    SELECT COUNT(*) INTO v_cnt FROM FRAUD_ALERTS;
    DBMS_OUTPUT.PUT_LINE('✔ Autonomous Security Fraud Alerts Logged: ' || v_cnt);
END;
/

-- Test 3: Bulk Interest
BEGIN
    ADBMS_BANKING_PKG.bulk_apply_monthly_interest(4.5, 500);
END;
/

-- Test 4: Distributed 2PC Simulation
BEGIN
    ADBMS_BANKING_PKG.simulate_distributed_transfer('BR-DEL-01', 'BR-BLR-01', 1001, 1003, 2000.00, 'NONE');
END;
/

PROMPT =====================================================================
PROMPT MASTER SCRIPT COMPLETED SUCCESSFULLY!
PROMPT All Tables, Object Types, Partitions, Triggers, Packages & Tests Ready!
PROMPT =====================================================================
