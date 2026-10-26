-- =====================================================================
-- ADVANCED DATABASE MANAGEMENT SYSTEMS (ADBMS) & ORACLE PL/SQL
-- SMART BANKING & ENTERPRISE FUND TRANSFER SYSTEM
-- File: 01_adbms_schema.sql
-- Concepts Demonstrated:
--   1. Object-Relational Database Management (ORDBMS) - User-Defined Types
--   2. Nested Types & VARRAYs
--   3. Range Partitioning on High-Volume Transaction Ledger
--   4. List Partitioning on Regional/Account Data
--   5. Sequences, Integrity Constraints, and Foreign Key Hierarchies
-- Compatible with: Oracle 11g / 12c / 19c / 21c / Oracle Live SQL
-- =====================================================================

-- Clean up existing objects
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

-- Drop existing types
BEGIN
    EXECUTE IMMEDIATE 'DROP TYPE KYC_DOC_TYP FORCE';
    EXECUTE IMMEDIATE 'DROP TYPE PHONE_ARRAY_TYP FORCE';
    EXECUTE IMMEDIATE 'DROP TYPE ADDRESS_TYP FORCE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

-- Drop sequences
BEGIN
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_ACC_NO';
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_TXN_ID';
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_LOG_ID';
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_FRAUD_ID';
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_DTXN_ID';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

-- =====================================================================
-- SECTION 1: ORDBMS - USER DEFINED OBJECT TYPES & METHODS
-- =====================================================================

-- 1.1 Object Type: Address Type with Member Function
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

-- 1.2 Object Type: KYC Document Record
CREATE OR REPLACE TYPE KYC_DOC_TYP AS OBJECT (
    doc_type        VARCHAR2(30),   -- e.g. 'AADHAAR', 'PAN', 'PASSPORT'
    doc_number      VARCHAR2(50),
    verified_status VARCHAR2(10)    -- 'VERIFIED', 'PENDING'
);
/

-- 1.3 VARRAY: Multiple Phone Numbers (Home, Mobile, Work)
CREATE OR REPLACE TYPE PHONE_ARRAY_TYP AS VARRAY(3) OF VARCHAR2(15);
/

-- =====================================================================
-- SECTION 2: SEQUENCES
-- =====================================================================
CREATE SEQUENCE SEQ_ACC_NO   START WITH 1001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_TXN_ID   START WITH 50001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_LOG_ID   START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_FRAUD_ID START WITH 80001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_DTXN_ID  START WITH 90001 INCREMENT BY 1 NOCACHE;

-- =====================================================================
-- SECTION 3: CORE BANKING SCHEMAS & BRANCH HIERARCHY
-- =====================================================================

-- 3.1 BRANCHES Table (For Multi-Branch / Distributed Banking)
CREATE TABLE BRANCHES (
    branch_code      VARCHAR2(10) PRIMARY KEY,
    branch_name      VARCHAR2(100) NOT NULL,
    city             VARCHAR2(50) NOT NULL,
    region           VARCHAR2(20) NOT NULL CHECK (region IN ('NORTH', 'SOUTH', 'EAST', 'WEST')),
    ifsc_code        VARCHAR2(15) UNIQUE NOT NULL,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3.2 ORDBMS Table: CUSTOMERS_OBJ with Embedded Object Types & VARRAY
CREATE TABLE CUSTOMERS_OBJ (
    customer_id      NUMBER(10) PRIMARY KEY,
    full_name        VARCHAR2(100) NOT NULL,
    email            VARCHAR2(100) UNIQUE NOT NULL,
    phones           PHONE_ARRAY_TYP,       -- VARRAY collection
    home_address     ADDRESS_TYP,           -- User Defined Object Type
    kyc_document     KYC_DOC_TYP,           -- Embedded Object Type
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3.3 ACCOUNTS Table (Standard relational model with Branch foreign key)
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

-- 3.4 ACCOUNTS_PARTITIONED (ADBMS: List Partitioning by Account Type)
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

-- 3.5 TRANSACTIONS (Base ledger)
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

-- 3.6 TRANSACTIONS_PARTITIONED (ADBMS: Range Partitioning by Transaction Date)
-- Enables Partition Pruning for massive historical banking logs
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

-- =====================================================================
-- SECTION 4: AUDIT, SECURITY & DISTRIBUTED TRANSACTION LEDGERS
-- =====================================================================

-- 4.1 Regular Audit Trail
CREATE TABLE AUDIT_LOGS (
    log_id           NUMBER(12) PRIMARY KEY,
    account_no       NUMBER(10) NOT NULL,
    action_type      VARCHAR2(35) NOT NULL,
    old_balance      NUMBER(12, 2),
    new_balance      NUMBER(12, 2),
    changed_by       VARCHAR2(50) DEFAULT USER,
    changed_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 4.2 FRAUD & SECURITY ALERTS (Autonomous Transaction Target)
-- This table receives logs even when financial transactions ROLLBACK!
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

-- 4.3 DISTRIBUTED TRANSACTIONS LOG (Simulating 2-Phase Commit Coordinator)
CREATE TABLE DISTRIBUTED_TXN_LOG (
    dtxn_id          NUMBER(12) PRIMARY KEY,
    global_xid       VARCHAR2(64) NOT NULL,
    source_branch    VARCHAR2(10) REFERENCES BRANCHES(branch_code),
    target_branch    VARCHAR2(10) REFERENCES BRANCHES(branch_code),
    from_account     NUMBER(10),
    to_account       NUMBER(10),
    amount           NUMBER(12, 2) NOT NULL,
    phase_1_status   VARCHAR2(20) DEFAULT 'PREPARED',    -- PREPARED / ABORTED
    phase_2_status   VARCHAR2(20) DEFAULT 'COMMITTED',   -- COMMITTED / ROLLED_BACK
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Comments for documentation & academic submission
COMMENT ON TABLE CUSTOMERS_OBJ IS 'ORDBMS Table storing User-Defined Types (Address, KYC) and VARRAY';
COMMENT ON TABLE TRANSACTIONS_PARTITIONED IS 'ADBMS Range Partitioned ledger for optimal query performance and partition pruning';
COMMENT ON TABLE ACCOUNTS_PARTITIONED IS 'ADBMS List Partitioned table organized by account product type';
COMMENT ON TABLE FRAUD_ALERTS IS 'Security repository populated via Autonomous Transactions immune to main transaction rollback';
COMMENT ON TABLE DISTRIBUTED_TXN_LOG IS 'State ledger tracking Two-Phase Commit (2PC) distributed banking protocol';
