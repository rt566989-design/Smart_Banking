-- =====================================================================
-- ADVANCED DATABASE MANAGEMENT SYSTEMS (ADBMS) & ORACLE PL/SQL
-- SMART BANKING & ENTERPRISE FUND TRANSFER SYSTEM
-- File: 05_adbms_package_body.sql
-- Description: Package Body implementation for ADBMS_BANKING_PKG
-- =====================================================================

CREATE OR REPLACE PACKAGE BODY ADBMS_BANKING_PKG AS

    -- =================================================================
    -- HELPER FUNCTION: Check if account exists and is ACTIVE
    -- =================================================================
    FUNCTION is_account_active(p_account_no IN NUMBER) RETURN BOOLEAN IS
        v_status ACCOUNTS.status%TYPE;
    BEGIN
        SELECT status INTO v_status 
        FROM ACCOUNTS 
        WHERE account_no = p_account_no;

        RETURN (v_status = 'ACTIVE');
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN FALSE;
    END is_account_active;

    -- =================================================================
    -- HELPER FUNCTION: Get current account balance
    -- =================================================================
    FUNCTION get_balance(p_account_no IN NUMBER) RETURN NUMBER IS
        v_balance ACCOUNTS.balance%TYPE;
    BEGIN
        SELECT balance INTO v_balance 
        FROM ACCOUNTS 
        WHERE account_no = p_account_no;

        RETURN v_balance;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20006, 'Account No ' || p_account_no || ' does not exist.');
    END get_balance;

    -- =================================================================
    -- PROCEDURE 1: ORDBMS Customer & Account Onboarding
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
    ) IS
        v_cust_id NUMBER(10);
    BEGIN
        IF p_initial_deposit < 0 THEN
            RAISE_APPLICATION_ERROR(-20004, 'Initial deposit cannot be negative.');
        END IF;

        -- 1. Create ORDBMS Customer Record with Object Types and VARRAY
        v_cust_id := SEQ_ACC_NO.NEXTVAL;
        INSERT INTO CUSTOMERS_OBJ (
            customer_id, full_name, email, phones, home_address, kyc_document
        ) VALUES (
            v_cust_id, p_name, p_email, p_phones, p_address, p_kyc
        );

        -- 2. Create Account Record
        p_account_no := v_cust_id;
        INSERT INTO ACCOUNTS (
            account_no, customer_id, branch_code, holder_name, email,
            phone, account_type, balance, daily_limit, status
        ) VALUES (
            p_account_no, v_cust_id, p_branch_code, p_name, p_email,
            CASE WHEN p_phones.COUNT > 0 THEN p_phones(1) ELSE NULL END,
            UPPER(p_account_type), p_initial_deposit, 50000.00, 'ACTIVE'
        );

        -- 3. Sync into List-Partitioned Accounts Table
        INSERT INTO ACCOUNTS_PARTITIONED (
            account_no, holder_name, branch_code, account_type, balance, status
        ) VALUES (
            p_account_no, p_name, p_branch_code, UPPER(p_account_type), p_initial_deposit, 'ACTIVE'
        );

        -- 4. Record Initial Deposit Transaction if applicable
        IF p_initial_deposit > 0 THEN
            INSERT INTO TRANSACTIONS (
                txn_id, to_account, txn_type, amount, status, remarks
            ) VALUES (
                SEQ_TXN_ID.NEXTVAL, p_account_no, 'DEPOSIT', p_initial_deposit, 'SUCCESS', 'Opening Deposit'
            );

            INSERT INTO TRANSACTIONS_PARTITIONED (
                txn_id, to_account, txn_type, amount, txn_date, status, remarks
            ) VALUES (
                SEQ_TXN_ID.CURRVAL, p_account_no, 'DEPOSIT', p_initial_deposit, TRUNC(SYSDATE), 'SUCCESS', 'Opening Deposit'
            );
        END IF;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('✔ ORDBMS Account successfully created: Acc No ' || p_account_no || ' for ' || p_name);
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            LOG_FRAUD_ALERT_AUTONOMOUS(0, 'MEDIUM', 'Account onboarding failure: ' || SQLERRM, p_initial_deposit);
            RAISE;
    END open_account_ordbms;

    -- =================================================================
    -- PROCEDURE 2: Deposit Money (Row-Level Locking & Partition Sync)
    -- =================================================================
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

        -- Acquire exclusive row-level pessimistic lock (WAIT 5 seconds to prevent indefinite deadlock)
        SELECT balance, status INTO v_current_bal, v_status
        FROM ACCOUNTS
        WHERE account_no = p_account_no
        FOR UPDATE WAIT 5;

        IF v_status <> 'ACTIVE' THEN
            RAISE_APPLICATION_ERROR(-20003, 'Account ' || p_account_no || ' is not ACTIVE (Current Status: ' || v_status || ').');
        END IF;

        -- Update balance
        UPDATE ACCOUNTS
        SET balance = balance + p_amount
        WHERE account_no = p_account_no;

        UPDATE ACCOUNTS_PARTITIONED
        SET balance = balance + p_amount
        WHERE account_no = p_account_no;

        v_txn_id := SEQ_TXN_ID.NEXTVAL;

        -- Ledger record in standard and Range-Partitioned tables
        INSERT INTO TRANSACTIONS (
            txn_id, to_account, txn_type, amount, status, remarks
        ) VALUES (
            v_txn_id, p_account_no, 'DEPOSIT', p_amount, 'SUCCESS', p_remarks
        );

        INSERT INTO TRANSACTIONS_PARTITIONED (
            txn_id, to_account, txn_type, amount, txn_date, status, remarks
        ) VALUES (
            v_txn_id, p_account_no, 'DEPOSIT', p_amount, TRUNC(SYSDATE), 'SUCCESS', p_remarks
        );

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('✔ Deposit successful: ₹' || p_amount || ' credited to Acc ' || p_account_no);
    EXCEPTION
        WHEN e_resource_busy THEN
            ROLLBACK;
            RAISE_APPLICATION_ERROR(-20007, 'Account ' || p_account_no || ' is locked by another concurrent session. Try again.');
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END deposit;

    -- =================================================================
    -- PROCEDURE 3: Withdraw Money with Fraud Guard
    -- =================================================================
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

        SELECT balance, status INTO v_current_bal, v_status
        FROM ACCOUNTS
        WHERE account_no = p_account_no
        FOR UPDATE WAIT 5;

        IF v_status <> 'ACTIVE' THEN
            RAISE_APPLICATION_ERROR(-20003, 'Account ' || p_account_no || ' is not ACTIVE.');
        END IF;

        IF v_current_bal < p_amount THEN
            -- Log security event autonomously before raising error!
            LOG_FRAUD_ALERT_AUTONOMOUS(
                p_account_no       => p_account_no,
                p_severity         => 'MEDIUM',
                p_reason           => 'Overdraft attempt: balance ₹' || v_current_bal || ', tried ₹' || p_amount,
                p_attempted_amount => p_amount
            );
            RAISE_APPLICATION_ERROR(-20002, 'Insufficient Funds: Current balance ₹' || v_current_bal || ', Requested: ₹' || p_amount);
        END IF;

        UPDATE ACCOUNTS
        SET balance = balance - p_amount
        WHERE account_no = p_account_no;

        UPDATE ACCOUNTS_PARTITIONED
        SET balance = balance - p_amount
        WHERE account_no = p_account_no;

        v_txn_id := SEQ_TXN_ID.NEXTVAL;

        INSERT INTO TRANSACTIONS (
            txn_id, from_account, txn_type, amount, status, remarks
        ) VALUES (
            v_txn_id, p_account_no, 'WITHDRAWAL', p_amount, 'SUCCESS', p_remarks
        );

        INSERT INTO TRANSACTIONS_PARTITIONED (
            txn_id, from_account, txn_type, amount, txn_date, status, remarks
        ) VALUES (
            v_txn_id, p_account_no, 'WITHDRAWAL', p_amount, TRUNC(SYSDATE), 'SUCCESS', p_remarks
        );

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('✔ Withdrawal successful: ₹' || p_amount || ' debited from Acc ' || p_account_no);
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END withdraw;

    -- =================================================================
    -- PROCEDURE 4: Atomic Transfer Funds with Deadlock-Free Lock Hierarchy
    -- =================================================================
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

        -- Establish Transaction Savepoint for partial rollback capability
        SAVEPOINT sp_transfer;

        -- ADBMS Concurrency Pattern: Strict Resource Ordering to prevent Deadlocks
        -- Always lock lower account number first!
        IF p_from_acc < p_to_acc THEN
            v_first_acc  := p_from_acc;
            v_second_acc := p_to_acc;
        ELSE
            v_first_acc  := p_to_acc;
            v_second_acc := p_from_acc;
        END IF;

        -- Acquire locks in strict numerical order
        SELECT status INTO v_sender_stat FROM ACCOUNTS WHERE account_no = v_first_acc FOR UPDATE WAIT 5;
        SELECT status INTO v_rcv_stat    FROM ACCOUNTS WHERE account_no = v_second_acc FOR UPDATE WAIT 5;

        -- Validate statuses
        IF NOT is_account_active(p_from_acc) THEN
            RAISE_APPLICATION_ERROR(-20003, 'Sender account ' || p_from_acc || ' is not ACTIVE.');
        END IF;
        IF NOT is_account_active(p_to_acc) THEN
            RAISE_APPLICATION_ERROR(-20003, 'Beneficiary account ' || p_to_acc || ' is not ACTIVE.');
        END IF;

        -- Check sender funds
        SELECT balance INTO v_sender_bal FROM ACCOUNTS WHERE account_no = p_from_acc;
        IF v_sender_bal < p_amount THEN
            LOG_FRAUD_ALERT_AUTONOMOUS(
                p_account_no       => p_from_acc,
                p_severity         => 'MEDIUM',
                p_reason           => 'Transfer failed: Insufficient balance ₹' || v_sender_bal || ', required ₹' || p_amount,
                p_attempted_amount => p_amount
            );
            RAISE_APPLICATION_ERROR(-20002, 'Insufficient funds in sender account.');
        END IF;

        -- Execute atomic updates
        UPDATE ACCOUNTS SET balance = balance - p_amount WHERE account_no = p_from_acc;
        UPDATE ACCOUNTS SET balance = balance + p_amount WHERE account_no = p_to_acc;

        UPDATE ACCOUNTS_PARTITIONED SET balance = balance - p_amount WHERE account_no = p_from_acc;
        UPDATE ACCOUNTS_PARTITIONED SET balance = balance + p_amount WHERE account_no = p_to_acc;

        v_txn_id := SEQ_TXN_ID.NEXTVAL;

        INSERT INTO TRANSACTIONS (
            txn_id, from_account, to_account, txn_type, amount, status, remarks
        ) VALUES (
            v_txn_id, p_from_acc, p_to_acc, 'TRANSFER', p_amount, 'SUCCESS', p_remarks
        );

        INSERT INTO TRANSACTIONS_PARTITIONED (
            txn_id, from_account, to_account, txn_type, amount, txn_date, status, remarks
        ) VALUES (
            v_txn_id, p_from_acc, p_to_acc, 'TRANSFER', p_amount, TRUNC(SYSDATE), 'SUCCESS', p_remarks
        );

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('✔ Transfer completed: ₹' || p_amount || ' sent from ' || p_from_acc || ' -> ' || p_to_acc);
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO sp_transfer;
            LOG_FRAUD_ALERT_AUTONOMOUS(
                p_account_no       => p_from_acc,
                p_severity         => 'HIGH',
                p_reason           => 'Transfer transaction aborted and rolled back: ' || SQLERRM,
                p_attempted_amount => p_amount
            );
            COMMIT; -- Commit remaining autonomous logs
            RAISE;
    END transfer_funds;

    -- =================================================================
    -- PROCEDURE 5: High-Performance Batch Processing using BULK COLLECT & FORALL
    -- (Essential ADBMS Topic: Bulk Bindings drastically reduce context switches)
    -- =================================================================
    PROCEDURE bulk_apply_monthly_interest (
        p_annual_rate IN NUMBER DEFAULT 4.5,
        p_batch_size  IN NUMBER DEFAULT 500
    ) IS
        CURSOR c_savings IS
            SELECT account_no, balance
            FROM ACCOUNTS
            WHERE account_type = 'SAVINGS'
              AND status = 'ACTIVE'
              AND balance > 0;

        TYPE t_num_list IS TABLE OF NUMBER;
        v_acc_list      t_num_list;
        v_bal_list      t_num_list;
        v_interest_list t_num_list := t_num_list();

        v_monthly_rate  NUMBER := (p_annual_rate / 100.0) / 12.0;
        v_total_updated NUMBER := 0;
        v_total_payout  NUMBER := 0;
    BEGIN
        OPEN c_savings;
        LOOP
            -- Bulk collect rows into memory array up to batch size
            FETCH c_savings BULK COLLECT INTO v_acc_list, v_bal_list LIMIT p_batch_size;
            EXIT WHEN v_acc_list.COUNT = 0;

            v_interest_list.EXTEND(v_acc_list.COUNT);

            -- Calculate interest in PGA memory (No SQL engine context switch)
            FOR i IN 1 .. v_acc_list.COUNT LOOP
                v_interest_list(i) := ROUND(v_bal_list(i) * v_monthly_rate, 2);
                v_total_payout     := v_total_payout + v_interest_list(i);
            END LOOP;

            -- High speed bulk update using FORALL
            FORALL i IN 1 .. v_acc_list.COUNT
                UPDATE ACCOUNTS
                SET balance = balance + v_interest_list(i)
                WHERE account_no = v_acc_list(i);

            -- Bulk insert transaction records
            FORALL i IN 1 .. v_acc_list.COUNT
                INSERT INTO TRANSACTIONS (
                    txn_id, to_account, txn_type, amount, status, remarks
                ) VALUES (
                    SEQ_TXN_ID.NEXTVAL,
                    v_acc_list(i),
                    'INTEREST',
                    v_interest_list(i),
                    'SUCCESS',
                    'Monthly Interest Credit @ ' || p_annual_rate || '%'
                );

            v_total_updated := v_total_updated + v_acc_list.COUNT;
            COMMIT; -- Commit batch chunk
        END LOOP;
        CLOSE c_savings;

        DBMS_OUTPUT.PUT_LINE('✔ Bulk Interest Processed: ' || v_total_updated || ' accounts updated | Total Interest Paid: ₹' || v_total_payout);
    EXCEPTION
        WHEN OTHERS THEN
            IF c_savings%ISOPEN THEN CLOSE c_savings; END IF;
            ROLLBACK;
            RAISE;
    END bulk_apply_monthly_interest;

    -- =================================================================
    -- PROCEDURE 6: Bulk Service Fee Deduction
    -- =================================================================
    PROCEDURE bulk_deduct_service_fee (
        p_fee_amount       IN NUMBER DEFAULT 150.00,
        p_min_balance_tier IN NUMBER DEFAULT 2000.00
    ) IS
        CURSOR c_low_bal IS
            SELECT account_no, balance
            FROM ACCOUNTS
            WHERE balance < p_min_balance_tier
              AND status = 'ACTIVE'
              AND balance >= p_fee_amount;

        TYPE t_num_list IS TABLE OF NUMBER;
        v_acc_list t_num_list;
        v_bal_list t_num_list;
    BEGIN
        OPEN c_low_bal;
        FETCH c_low_bal BULK COLLECT INTO v_acc_list, v_bal_list;
        CLOSE c_low_bal;

        IF v_acc_list.COUNT > 0 THEN
            FORALL i IN 1 .. v_acc_list.COUNT SAVE EXCEPTIONS
                UPDATE ACCOUNTS
                SET balance = balance - p_fee_amount
                WHERE account_no = v_acc_list(i);

            FORALL i IN 1 .. v_acc_list.COUNT
                INSERT INTO TRANSACTIONS (
                    txn_id, from_account, txn_type, amount, status, remarks
                ) VALUES (
                    SEQ_TXN_ID.NEXTVAL,
                    v_acc_list(i),
                    'FEE',
                    p_fee_amount,
                    'SUCCESS',
                    'Monthly Low Balance Maintenance Fee'
                );

            COMMIT;
            DBMS_OUTPUT.PUT_LINE('✔ Bulk maintenance charges applied to ' || v_acc_list.COUNT || ' accounts.');
        ELSE
            DBMS_OUTPUT.PUT_LINE('ℹ No accounts eligible for service fee deduction.');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END bulk_deduct_service_fee;

    -- =================================================================
    -- PROCEDURE 7: Distributed 2-Phase Commit (2PC) Banking Simulator
    -- =================================================================
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

        -- -------------------------------------------------------------
        -- PHASE 1: PREPARE (Voting & Resource Lock verification)
        -- -------------------------------------------------------------
        IF p_simulate_fail = 'PREPARE_FAIL' THEN
            -- Simulate network partition or branch node crash
            INSERT INTO DISTRIBUTED_TXN_LOG (
                dtxn_id, global_xid, source_branch, target_branch,
                from_account, to_account, amount, phase_1_status, phase_2_status
            ) VALUES (
                v_dtxn_id, v_gxid, p_source_branch, p_target_branch,
                p_from_acc, p_to_acc, p_amount, 'VOTE_ABORT', 'GLOBAL_ROLLED_BACK'
            );
            COMMIT;

            LOG_FRAUD_ALERT_AUTONOMOUS(
                p_account_no       => p_from_acc,
                p_severity         => 'CRITICAL',
                p_reason           => 'Distributed 2PC Protocol: Target Branch ' || p_target_branch || ' voted ABORT during Phase 1.',
                p_attempted_amount => p_amount
            );

            RAISE_APPLICATION_ERROR(-20015, 'Distributed 2PC Phase 1 Failed: Branch ' || p_target_branch || ' reported node unavailable. Global Transaction Aborted.');
        END IF;

        -- Record Phase 1 Success
        INSERT INTO DISTRIBUTED_TXN_LOG (
            dtxn_id, global_xid, source_branch, target_branch,
            from_account, to_account, amount, phase_1_status, phase_2_status
        ) VALUES (
            v_dtxn_id, v_gxid, p_source_branch, p_target_branch,
            p_from_acc, p_to_acc, p_amount, 'VOTE_COMMIT', 'PREPARED'
        );

        -- -------------------------------------------------------------
        -- PHASE 2: GLOBAL COMMIT
        -- -------------------------------------------------------------
        transfer_funds(p_from_acc, p_to_acc, p_amount, 'Distributed 2PC Transfer: ' || v_gxid);

        UPDATE DISTRIBUTED_TXN_LOG
        SET phase_2_status = 'GLOBAL_COMMITTED'
        WHERE dtxn_id = v_dtxn_id;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('✔ Distributed 2PC Transaction successfully committed! Global XID: ' || v_gxid);
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            UPDATE DISTRIBUTED_TXN_LOG
            SET phase_2_status = 'GLOBAL_ROLLED_BACK'
            WHERE dtxn_id = v_dtxn_id;
            COMMIT;
            RAISE;
    END simulate_distributed_transfer;

    -- =================================================================
    -- FUNCTION: Pipelined Mini Statement
    -- =================================================================
    FUNCTION stream_mini_statement (
        p_account_no IN NUMBER,
        p_limit      IN NUMBER DEFAULT 10
    ) RETURN t_statement_table PIPELINED IS
        v_out_row t_statement_row;
        CURSOR c_txns IS
            SELECT 
                txn_id,
                TO_CHAR(txn_date, 'YYYY-MM-DD HH24:MI:SS') AS dt_str,
                txn_type,
                amount,
                NVL(to_account, from_account) AS counterparty,
                remarks
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

            PIPE ROW(v_out_row); -- Stream row to client without caching entire table
        END LOOP;
        RETURN;
    END stream_mini_statement;

END ADBMS_BANKING_PKG;
/
