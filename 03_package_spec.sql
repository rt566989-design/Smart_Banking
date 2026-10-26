-- =====================================================================
-- SMART BANKING & FUND TRANSFER SYSTEM
-- File: 03_package_spec.sql
-- Description: Package Specification for BANKING_PKG
-- =====================================================================

CREATE OR REPLACE PACKAGE BANKING_PKG AS
    -- Custom Exceptions
    e_insufficient_funds   EXCEPTION;
    e_account_inactive     EXCEPTION;
    e_invalid_amount       EXCEPTION;
    e_same_account         EXCEPTION;
    e_account_not_found    EXCEPTION;

    PRAGMA EXCEPTION_INIT(e_insufficient_funds, -20002);
    PRAGMA EXCEPTION_INIT(e_account_inactive,   -20003);
    PRAGMA EXCEPTION_INIT(e_invalid_amount,     -20004);
    PRAGMA EXCEPTION_INIT(e_same_account,       -20005);
    PRAGMA EXCEPTION_INIT(e_account_not_found,  -20006);

    -- 1. Open a new customer account
    PROCEDURE open_account(
        p_name            IN  VARCHAR2,
        p_email           IN  VARCHAR2,
        p_phone           IN  VARCHAR2,
        p_type            IN  VARCHAR2,
        p_initial_deposit IN  NUMBER,
        p_account_no      OUT NUMBER
    );

    -- 2. Deposit money into an account
    PROCEDURE deposit(
        p_account_no IN NUMBER,
        p_amount     IN NUMBER,
        p_remarks    IN VARCHAR2 DEFAULT 'Cash Deposit'
    );

    -- 3. Withdraw money from an account
    PROCEDURE withdraw(
        p_account_no IN NUMBER,
        p_amount     IN NUMBER,
        p_remarks    IN VARCHAR2 DEFAULT 'Cash Withdrawal'
    );

    -- 4. Transfer funds between two accounts (Atomicity with SAVEPOINT/ROLLBACK)
    PROCEDURE transfer_funds(
        p_from_acc IN NUMBER,
        p_to_acc   IN NUMBER,
        p_amount   IN NUMBER,
        p_remarks  IN VARCHAR2 DEFAULT 'Fund Transfer'
    );

    -- 5. Batch interest calculation for all SAVINGS accounts using CURSOR
    PROCEDURE apply_monthly_interest(
        p_annual_rate IN NUMBER DEFAULT 4.0
    );

    -- 6. Print formatted mini-statement using DBMS_OUTPUT and CURSOR
    PROCEDURE print_mini_statement(
        p_account_no IN NUMBER,
        p_limit      IN NUMBER DEFAULT 5
    );

    -- 7. Functions
    FUNCTION get_balance(p_account_no IN NUMBER) RETURN NUMBER;
    FUNCTION is_account_active(p_account_no IN NUMBER) RETURN BOOLEAN;
    FUNCTION calculate_monthly_interest(
        p_account_no  IN NUMBER, 
        p_annual_rate IN NUMBER DEFAULT 4.0
    ) RETURN NUMBER;

END BANKING_PKG;
/
