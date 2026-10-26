-- =====================================================================
-- SMART BANKING & FUND TRANSFER SYSTEM
-- File: 01_schema.sql
-- Description: Tables, Sequences, and Constraints
-- Compatible with: Oracle 11g / 12c / 19c / 21c / Oracle Live SQL
-- =====================================================================

-- Drop existing tables (clean start)
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE AUDIT_LOGS CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE TRANSACTIONS CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE ACCOUNTS CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_ACC_NO';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_TXN_ID';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_LOG_ID';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

-- 1. Sequences for Auto-generating IDs
CREATE SEQUENCE SEQ_ACC_NO START WITH 1001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_TXN_ID START WITH 50001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_LOG_ID START WITH 1 INCREMENT BY 1 NOCACHE;

-- 2. ACCOUNTS Table
CREATE TABLE ACCOUNTS (
    account_no       NUMBER(10) PRIMARY KEY,
    holder_name      VARCHAR2(100) NOT NULL,
    email            VARCHAR2(100) UNIQUE NOT NULL,
    phone            VARCHAR2(15),
    account_type     VARCHAR2(15) DEFAULT 'SAVINGS' 
                     CHECK (account_type IN ('SAVINGS', 'CURRENT', 'SALARY')),
    balance          NUMBER(12, 2) DEFAULT 0.00 NOT NULL 
                     CHECK (balance >= 0),
    status           VARCHAR2(15) DEFAULT 'ACTIVE' 
                     CHECK (status IN ('ACTIVE', 'DORMANT', 'FROZEN', 'CLOSED')),
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3. TRANSACTIONS Table (Records all money movements)
CREATE TABLE TRANSACTIONS (
    txn_id           NUMBER(12) PRIMARY KEY,
    from_account     NUMBER(10) REFERENCES ACCOUNTS(account_no),
    to_account       NUMBER(10) REFERENCES ACCOUNTS(account_no),
    txn_type         VARCHAR2(15) NOT NULL 
                     CHECK (txn_type IN ('DEPOSIT', 'WITHDRAWAL', 'TRANSFER', 'INTEREST')),
    amount           NUMBER(12, 2) NOT NULL CHECK (amount > 0),
    txn_date         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status           VARCHAR2(15) DEFAULT 'SUCCESS' 
                     CHECK (status IN ('SUCCESS', 'FAILED')),
    remarks          VARCHAR2(200)
);

-- 4. AUDIT_LOGS Table (Trigger writes here whenever balance changes)
CREATE TABLE AUDIT_LOGS (
    log_id           NUMBER(12) PRIMARY KEY,
    account_no       NUMBER(10) NOT NULL,
    action_type      VARCHAR2(30) NOT NULL,
    old_balance      NUMBER(12, 2),
    new_balance      NUMBER(12, 2),
    changed_by       VARCHAR2(50) DEFAULT USER,
    changed_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Comments for Schema clarity
COMMENT ON TABLE ACCOUNTS IS 'Stores customer account information and balances';
COMMENT ON TABLE TRANSACTIONS IS 'Maintains transaction ledger for all deposits, withdrawals, and transfers';
COMMENT ON TABLE AUDIT_LOGS IS 'Auto-populated audit trail via triggers for financial auditing';
