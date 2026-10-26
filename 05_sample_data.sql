-- =====================================================================
-- SMART BANKING & FUND TRANSFER SYSTEM
-- File: 05_sample_data.sql
-- Description: Inserts initial sample accounts for testing
-- =====================================================================

SET SERVEROUTPUT ON;

DECLARE
    v_acc1 NUMBER;
    v_acc2 NUMBER;
    v_acc3 NUMBER;
    v_acc4 NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- Seeding Sample Bank Accounts ---');

    -- Account 1: Rahul Sharma (Savings)
    BANKING_PKG.open_account(
        p_name            => 'Rahul Sharma',
        p_email           => 'rahul.sharma@example.com',
        p_phone           => '9876543210',
        p_type            => 'SAVINGS',
        p_initial_deposit => 25000.00,
        p_account_no      => v_acc1
    );

    -- Account 2: Priya Patel (Salary)
    BANKING_PKG.open_account(
        p_name            => 'Priya Patel',
        p_email           => 'priya.patel@example.com',
        p_phone           => '9823456781',
        p_type            => 'SALARY',
        p_initial_deposit => 50000.00,
        p_account_no      => v_acc2
    );

    -- Account 3: Amit Verma (Current)
    BANKING_PKG.open_account(
        p_name            => 'Amit Verma',
        p_email           => 'amit.verma@example.com',
        p_phone           => '9811223344',
        p_type            => 'CURRENT',
        p_initial_deposit => 100000.00,
        p_account_no      => v_acc3
    );

    -- Account 4: Neha Singh (Savings with low balance)
    BANKING_PKG.open_account(
        p_name            => 'Neha Singh',
        p_email           => 'neha.singh@example.com',
        p_phone           => '9899887766',
        p_type            => 'SAVINGS',
        p_initial_deposit => 1500.00,
        p_account_no      => v_acc4
    );

    DBMS_OUTPUT.PUT_LINE('✔ 4 sample accounts seeded successfully.');
END;
/
