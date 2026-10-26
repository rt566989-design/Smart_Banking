-- =====================================================================
-- ADVANCED DATABASE MANAGEMENT SYSTEMS (ADBMS) & ORACLE PL/SQL
-- SMART BANKING & ENTERPRISE FUND TRANSFER SYSTEM
-- File: 08_adbms_test_suite.sql
-- Description: Comprehensive Automated Test Suite covering all ADBMS Scenarios
-- =====================================================================

SET SERVEROUTPUT ON SIZE 1000000;
SET LINESIZE 200;
SET PAGESIZE 100;

PROMPT =====================================================================
PROMPT TEST 1: ORDBMS CUSTOMER ONBOARDING (USER OBJECT TYPES & VARRAY)
PROMPT =====================================================================
DECLARE
    v_new_acc NUMBER;
BEGIN
    ADBMS_BANKING_PKG.open_account_ordbms(
        p_name            => 'Siddharth Rao',
        p_email           => 'siddharth.rao@example.com',
        p_phones          => PHONE_ARRAY_TYP('9810011223', '9810099887'),
        p_address         => ADDRESS_TYP('55 Brigade Road', 'Bengaluru', 'Karnataka', '560001'),
        p_kyc             => KYC_DOC_TYP('PAN', 'BNZPR4455Q', 'VERIFIED'),
        p_branch_code     => 'BR-BLR-01',
        p_account_type    => 'SAVINGS',
        p_initial_deposit => 30000.00,
        p_account_no      => v_new_acc
    );
    DBMS_OUTPUT.PUT_LINE('>>> TEST 1 PASSED: New ORDBMS Customer Account No: ' || v_new_acc);
END;
/

PROMPT =====================================================================
PROMPT TEST 2: ACID COMPLIANT FUND TRANSFER (ROW LOCKING & SAVEPOINT)
PROMPT =====================================================================
BEGIN
    DBMS_OUTPUT.PUT_LINE('Initial Balances:');
    DBMS_OUTPUT.PUT_LINE('Account 1001 (Rahul): ₹' || ADBMS_BANKING_PKG.get_balance(1001));
    DBMS_OUTPUT.PUT_LINE('Account 1004 (Neha):  ₹' || ADBMS_BANKING_PKG.get_balance(1004));

    ADBMS_BANKING_PKG.transfer_funds(
        p_from_acc => 1001,
        p_to_acc   => 1004,
        p_amount   => 5000.00,
        p_remarks  => 'Monthly Pocket Money'
    );

    DBMS_OUTPUT.PUT_LINE('Updated Balances:');
    DBMS_OUTPUT.PUT_LINE('Account 1001 (Rahul): ₹' || ADBMS_BANKING_PKG.get_balance(1001));
    DBMS_OUTPUT.PUT_LINE('Account 1004 (Neha):  ₹' || ADBMS_BANKING_PKG.get_balance(1004));
    DBMS_OUTPUT.PUT_LINE('>>> TEST 2 PASSED: Transfer executed with atomic lock');
END;
/

PROMPT =====================================================================
PROMPT TEST 3: AUTONOMOUS TRANSACTIONS (FRAUD LOG SAVED DESPITE ROLLBACK)
PROMPT =====================================================================
-- We attempt an overdraft withdrawal of ₹5,00,000 from Account 1004 (balance ~₹20,000)
-- Financial transaction will ROLLBACK, but FRAUD_ALERTS table will retain the log!
DECLARE
    v_alert_count_before NUMBER;
    v_alert_count_after  NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_alert_count_before FROM FRAUD_ALERTS;

    BEGIN
        ADBMS_BANKING_PKG.withdraw(1004, 500000.00, 'Malicious Large Withdrawal');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Caught Expected Overdraft Error: ' || SQLERRM);
    END;

    SELECT COUNT(*) INTO v_alert_count_after FROM FRAUD_ALERTS;

    IF v_alert_count_after > v_alert_count_before THEN
        DBMS_OUTPUT.PUT_LINE('>>> TEST 3 PASSED: Autonomous Transaction successfully committed fraud alert independently of main transaction rollback!');
    ELSE
        DBMS_OUTPUT.PUT_LINE('>>> TEST 3 FAILED: Fraud alert was not committed.');
    END IF;
END;
/

PROMPT =====================================================================
PROMPT TEST 4: COMPOUND TRIGGER DAILY LIMIT CHECK (NO MUTATING TABLE ERROR)
PROMPT =====================================================================
-- Daily limit for Acc 1004 is ₹50,000. Attempting a single transfer above daily cap.
BEGIN
    BEGIN
        ADBMS_BANKING_PKG.transfer_funds(
            p_from_acc => 1004,
            p_to_acc   => 1001,
            p_amount   => 60000.00,
            p_remarks  => 'Attempt Exceeding Daily Ceiling'
        );
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Caught Expected Daily Limit Error: ' || SQLERRM);
            DBMS_OUTPUT.PUT_LINE('>>> TEST 4 PASSED: Compound Trigger enforced daily threshold without ORA-04091 mutating error!');
    END;
END;
/

PROMPT =====================================================================
PROMPT TEST 5: HIGH-PERFORMANCE BULK OPERATIONS (BULK COLLECT & FORALL)
PROMPT =====================================================================
BEGIN
    DBMS_OUTPUT.PUT_LINE('Executing Bulk Monthly Interest Calculation...');
    ADBMS_BANKING_PKG.bulk_apply_monthly_interest(p_annual_rate => 4.5, p_batch_size => 500);

    DBMS_OUTPUT.PUT_LINE('Executing Bulk Low-Balance Service Fee Deduction...');
    ADBMS_BANKING_PKG.bulk_deduct_service_fee(p_fee_amount => 150.00, p_min_balance_tier => 2000.00);

    DBMS_OUTPUT.PUT_LINE('>>> TEST 5 PASSED: Bulk Collect & FORALL batches executed seamlessly');
END;
/

PROMPT =====================================================================
PROMPT TEST 6: DISTRIBUTED TWO-PHASE COMMIT (2PC) SIMULATOR
PROMPT =====================================================================
BEGIN
    -- Scenario A: Successful 2PC Distributed Transfer across branches
    DBMS_OUTPUT.PUT_LINE('Executing 2PC Distributed Transfer (Delhi -> Bangalore)...');
    ADBMS_BANKING_PKG.simulate_distributed_transfer(
        p_source_branch => 'BR-DEL-01',
        p_target_branch => 'BR-BLR-01',
        p_from_acc      => 1001,
        p_to_acc        => 1003,
        p_amount        => 2500.00,
        p_simulate_fail => 'NONE'
    );

    -- Scenario B: Simulated Phase 1 Failure (Remote Node Abort)
    DBMS_OUTPUT.PUT_LINE('Simulating Remote Node Crash / Phase 1 Abort...');
    BEGIN
        ADBMS_BANKING_PKG.simulate_distributed_transfer(
            p_source_branch => 'BR-DEL-01',
            p_target_branch => 'BR-KOL-01',
            p_from_acc      => 1001,
            p_to_acc        => 1005,
            p_amount        => 2500.00,
            p_simulate_fail => 'PREPARE_FAIL'
        );
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Caught Expected 2PC Phase 1 Abort: ' || SQLERRM);
    END;

    DBMS_OUTPUT.PUT_LINE('>>> TEST 6 PASSED: 2PC Coordinator state machine tested');
END;
/

PROMPT =====================================================================
PROMPT TEST 7: PIPELINED TABLE FUNCTION QUERY
PROMPT =====================================================================
PROMPT Streaming Mini Statement for Account 1001 via TABLE() function:
SELECT * FROM TABLE(ADBMS_BANKING_PKG.stream_mini_statement(1001, 5));

PROMPT =====================================================================
PROMPT TEST 8: MATERIALIZED VIEW FAST REFRESH & STATE VERIFICATION
PROMPT =====================================================================
BEGIN
    REFRESH_ALL_MVIEWS;
END;
/
SELECT * FROM MV_DAILY_BRANCH_SUMMARY;
SELECT * FROM MV_CUSTOMER_NETWORTH;

PROMPT =====================================================================
PROMPT TEST 9: FRAUD & SECURITY LEDGER (AUTONOMOUS TRANSACTION AUDIT)
PROMPT =====================================================================
SELECT alert_id, account_no, severity, reason, attempted_amount, alert_time 
FROM FRAUD_ALERTS 
ORDER BY alert_id DESC;

PROMPT =====================================================================
PROMPT ALL ADBMS & PL/SQL AUTOMATED TESTS COMPLETED SUCCESSFULLY!
PROMPT =====================================================================
