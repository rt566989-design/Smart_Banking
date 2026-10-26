-- =====================================================================
-- SMART BANKING & FUND TRANSFER SYSTEM
-- File: 06_test_cases.sql
-- Description: Interactive test cases showcasing all PL/SQL capabilities
-- =====================================================================

SET SERVEROUTPUT ON SIZE 1000000;

PROMPT ================================================================
PROMPT 1. TESTING DEPOSIT & WITHDRAWAL
PROMPT ================================================================
BEGIN
    -- Deposit ₹10,000 in Acc 1001
    BANKING_PKG.deposit(1001, 10000.00, 'Bonus Deposit');

    -- Withdraw ₹3,000 from Acc 1002
    BANKING_PKG.withdraw(1002, 3000.00, 'ATM Cash Withdrawal');
END;
/

PROMPT ================================================================
PROMPT 2. TESTING SUCCESSFUL FUND TRANSFER
PROMPT ================================================================
BEGIN
    -- Rahul (1001) transfers ₹5,000 to Priya (1002)
    BANKING_PKG.transfer_funds(
        p_from_acc => 1001,
        p_to_acc   => 1002,
        p_amount   => 5000.00,
        p_remarks  => 'Rent Share Payment'
    );
END;
/

PROMPT ================================================================
PROMPT 3. TESTING EXCEPTION HANDLING: INSUFFICIENT BALANCE
PROMPT ================================================================
BEGIN
    -- Neha (1004) only has ~₹1,500, trying to transfer ₹50,000
    DBMS_OUTPUT.PUT_LINE('Attempting transfer greater than available balance...');
    BANKING_PKG.transfer_funds(
        p_from_acc => 1004,
        p_to_acc   => 1001,
        p_amount   => 50000.00,
        p_remarks  => 'Large Transfer (Expected to fail)'
    );
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Caught Expected Error: ' || SQLERRM);
END;
/

PROMPT ================================================================
PROMPT 4. TESTING CURSOR: APPLY MONTHLY INTEREST TO ALL SAVINGS ACCOUNTS
PROMPT ================================================================
BEGIN
    -- Apply 4.5% annual interest
    BANKING_PKG.apply_monthly_interest(p_annual_rate => 4.5);
END;
/

PROMPT ================================================================
PROMPT 5. TESTING MINI-STATEMENT GENERATION
PROMPT ================================================================
BEGIN
    BANKING_PKG.print_mini_statement(1001, 5);
    BANKING_PKG.print_mini_statement(1002, 5);
END;
/

PROMPT ================================================================
PROMPT 6. VERIFYING TRIGGER AUDIT LOGS
PROMPT ================================================================
COL log_id FORMAT 9999
COL account_no FORMAT 999999
COL action_type FORMAT A18
COL old_balance FORMAT 999999.99
COL new_balance FORMAT 999999.99
COL changed_by FORMAT A12
COL changed_at FORMAT A25

SELECT log_id, account_no, action_type, old_balance, new_balance, changed_by, 
       TO_CHAR(changed_at, 'YYYY-MM-DD HH24:MI:SS') AS changed_at
FROM AUDIT_LOGS
ORDER BY log_id ASC;
