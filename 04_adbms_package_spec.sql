-- =====================================================================
-- ADVANCED DATABASE MANAGEMENT SYSTEMS (ADBMS) & ORACLE PL/SQL
-- SMART BANKING & ENTERPRISE FUND TRANSFER SYSTEM
-- File: 04_adbms_package_spec.sql
-- Description: Package Specification for ADBMS_BANKING_PKG
-- Concepts Demonstrated:
--   1. Object-Relational Parameter Handling (Types, VARRAYs)
--   2. High-Performance Bulk Processing (BULK COLLECT & FORALL)
--   3. Pipelined Table Functions (Streaming Memory-Efficient Data)
--   4. Distributed Two-Phase Commit (2PC) Banking Simulator
--   5. Autonomous Transaction Security Integration
-- =====================================================================

CREATE OR REPLACE PACKAGE ADBMS_BANKING_PKG AS

    -- =================================================================
    -- SECTION 1: CUSTOM EXCEPTION DEFINITIONS & PRAGMAS
    -- =================================================================
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
    PRAGMA EXCEPTION_INIT(e_resource_busy,        -00054); -- ORA-00054: resource busy (NOWAIT lock)
    PRAGMA EXCEPTION_INIT(e_daily_limit_exceeded, -20010);
    PRAGMA EXCEPTION_INIT(e_2pc_prepare_failed,   -20015);

    -- =================================================================
    -- SECTION 2: PIPELINED TABLE TYPE DECLARATIONS
    -- =================================================================
    TYPE t_statement_row IS RECORD (
        txn_id       NUMBER(12),
        txn_date     VARCHAR2(30),
        txn_type     VARCHAR2(15),
        amount       NUMBER(12, 2),
        counterparty NUMBER(10),
        remarks      VARCHAR2(200)
    );
    TYPE t_statement_table IS TABLE OF t_statement_row;

    -- =================================================================
    -- SECTION 3: ORDBMS CUSTOMER ONBOARDING
    -- =================================================================
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

    -- =================================================================
    -- SECTION 4: ATOMIC CORE BANKING TRANSACTIONS (ACID COMPLIANT)
    -- =================================================================
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

    -- =================================================================
    -- SECTION 5: HIGH-PERFORMANCE BULK OPERATIONS (ADBMS CORE TOPIC)
    -- =================================================================
    -- High throughput batch interest calculation using BULK COLLECT & FORALL
    PROCEDURE bulk_apply_monthly_interest (
        p_annual_rate IN NUMBER DEFAULT 4.5,
        p_batch_size  IN NUMBER DEFAULT 500
    );

    -- Bulk service fee deduction across dormant / low-balance accounts
    PROCEDURE bulk_deduct_service_fee (
        p_fee_amount       IN NUMBER DEFAULT 150.00,
        p_min_balance_tier IN NUMBER DEFAULT 2000.00
    );

    -- =================================================================
    -- SECTION 6: DISTRIBUTED 2-PHASE COMMIT (2PC) SIMULATOR
    -- =================================================================
    -- Simulates cross-branch distributed transactions with Coordinator state
    PROCEDURE simulate_distributed_transfer (
        p_source_branch IN VARCHAR2,
        p_target_branch IN VARCHAR2,
        p_from_acc      IN NUMBER,
        p_to_acc        IN NUMBER,
        p_amount        IN NUMBER,
        p_simulate_fail IN VARCHAR2 DEFAULT 'NONE' -- 'PREPARE_FAIL', 'NONE'
    );

    -- =================================================================
    -- SECTION 7: PIPELINED TABLE FUNCTION & ANALYTICAL UTILITIES
    -- =================================================================
    -- Pipelined streaming statement for ultra-low PGA memory usage
    FUNCTION stream_mini_statement (
        p_account_no IN NUMBER,
        p_limit      IN NUMBER DEFAULT 10
    ) RETURN t_statement_table PIPELINED;

    -- Financial lookup functions
    FUNCTION get_balance (p_account_no IN NUMBER) RETURN NUMBER;
    FUNCTION is_account_active (p_account_no IN NUMBER) RETURN BOOLEAN;

END ADBMS_BANKING_PKG;
/
