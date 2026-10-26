-- =====================================================================
-- SMART BANKING & FUND TRANSFER SYSTEM
-- File: 04_package_body.sql
-- Description: Package Body implementation for BANKING_PKG
-- =====================================================================

CREATE OR REPLACE PACKAGE BODY BANKING_PKG AS

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
    -- FUNCTION: Get current account balance
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
            RAISE_APPLICATION_ERROR(-20006, 'Account number ' || p_account_no || ' does not exist.');
    END get_balance;

    -- =================================================================
    -- FUNCTION: Calculate single month interest for an account
    -- =================================================================
    FUNCTION calculate_monthly_interest(
        p_account_no  IN NUMBER, 
        p_annual_rate IN NUMBER DEFAULT 4.0
    ) RETURN NUMBER IS
        v_balance NUMBER;
    BEGIN
        v_balance := get_balance(p_account_no);
        RETURN ROUND(v_balance * (p_annual_rate / 100) / 12, 2);
    END calculate_monthly_interest;

    -- =================================================================
    -- PROCEDURE 1: Open a new account
    -- =================================================================
    PROCEDURE open_account(
        p_name            IN  VARCHAR2,
        p_email           IN  VARCHAR2,
        p_phone           IN  VARCHAR2,
        p_type            IN  VARCHAR2,
        p_initial_deposit IN  NUMBER,
        p_account_no      OUT NUMBER
    ) IS
    BEGIN
        IF p_initial_deposit < 0 THEN
            RAISE_APPLICATION_ERROR(-20004, 'Initial deposit cannot be negative.');
        END IF;

        p_account_no := SEQ_ACC_NO.NEXTVAL;

        INSERT INTO ACCOUNTS (
            account_no, holder_name, email, phone, account_type, balance, status
        ) VALUES (
            p_account_no, p_name, p_email, p_phone, UPPER(p_type), p_initial_deposit, 'ACTIVE'
        );

        -- If initial deposit > 0, record opening transaction
        IF p_initial_deposit > 0 THEN
            INSERT INTO TRANSACTIONS (
                txn_id, to_account, txn_type, amount, status, remarks
            ) VALUES (
                SEQ_TXN_ID.NEXTVAL, p_account_no, 'DEPOSIT', p_initial_deposit, 'SUCCESS', 'Opening Deposit'
            );
        END IF;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('✔ Account created successfully! Account No: ' || p_account_no || ' | Holder: ' || p_name);
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            DBMS_OUTPUT.PUT_LINE('✘ Failed to create account: ' || SQLERRM);
            RAISE;
    END open_account;

    -- =================================================================
    -- PROCEDURE 2: Deposit money
    -- =================================================================
    PROCEDURE deposit(
        p_account_no IN NUMBER,
        p_amount     IN NUMBER,
        p_remarks    IN VARCHAR2 DEFAULT 'Cash Deposit'
    ) IS
    BEGIN
        IF p_amount <= 0 THEN
            RAISE_APPLICATION_ERROR(-20004, 'Deposit amount must be greater than zero.');
        END IF;

        IF NOT is_account_active(p_account_no) THEN
            RAISE_APPLICATION_ERROR(-20003, 'Account ' || p_account_no || ' is inactive or does not exist.');
        END IF;

        UPDATE ACCOUNTS 
        SET balance = balance + p_amount 
        WHERE account_no = p_account_no;

        INSERT INTO TRANSACTIONS (
            txn_id, to_account, txn_type, amount, status, remarks
        ) VALUES (
            SEQ_TXN_ID.NEXTVAL, p_account_no, 'DEPOSIT', p_amount, 'SUCCESS', p_remarks
        );

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('✔ Deposit of ₹' || p_amount || ' credited to Acc: ' || p_account_no || 
                             ' | New Balance: ₹' || get_balance(p_account_no));
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            DBMS_OUTPUT.PUT_LINE('✘ Deposit failed: ' || SQLERRM);
            RAISE;
    END deposit;

    -- =================================================================
    -- PROCEDURE 3: Withdraw money
    -- =================================================================
    PROCEDURE withdraw(
        p_account_no IN NUMBER,
        p_amount     IN NUMBER,
        p_remarks    IN VARCHAR2 DEFAULT 'Cash Withdrawal'
    ) IS
        v_current_balance NUMBER;
    BEGIN
        IF p_amount <= 0 THEN
            RAISE_APPLICATION_ERROR(-20004, 'Withdrawal amount must be greater than zero.');
        END IF;

        IF NOT is_account_active(p_account_no) THEN
            RAISE_APPLICATION_ERROR(-20003, 'Account ' || p_account_no || ' is not active.');
        END IF;

        SELECT balance INTO v_current_balance 
        FROM ACCOUNTS 
        WHERE account_no = p_account_no 
        FOR UPDATE; -- Row-level lock

        IF v_current_balance < p_amount THEN
            RAISE_APPLICATION_ERROR(-20002, 'Insufficient balance. Available: ₹' || v_current_balance || 
                                           ', Requested: ₹' || p_amount);
        END IF;

        UPDATE ACCOUNTS 
        SET balance = balance - p_amount 
        WHERE account_no = p_account_no;

        INSERT INTO TRANSACTIONS (
            txn_id, from_account, txn_type, amount, status, remarks
        ) VALUES (
            SEQ_TXN_ID.NEXTVAL, p_account_no, 'WITHDRAWAL', p_amount, 'SUCCESS', p_remarks
        );

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('✔ Withdrawal of ₹' || p_amount || ' debited from Acc: ' || p_account_no || 
                             ' | Remaining Balance: ₹' || (v_current_balance - p_amount));
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            DBMS_OUTPUT.PUT_LINE('✘ Withdrawal failed: ' || SQLERRM);
            RAISE;
    END withdraw;

    -- =================================================================
    -- PROCEDURE 4: Fund Transfer (Safe Transaction with SAVEPOINT)
    -- =================================================================
    PROCEDURE transfer_funds(
        p_from_acc IN NUMBER,
        p_to_acc   IN NUMBER,
        p_amount   IN NUMBER,
        p_remarks  IN VARCHAR2 DEFAULT 'Fund Transfer'
    ) IS
        v_from_balance NUMBER;
        v_to_status    ACCOUNTS.status%TYPE;
    BEGIN
        -- 1. Basic validation
        IF p_from_acc = p_to_acc THEN
            RAISE_APPLICATION_ERROR(-20005, 'Sender and Receiver account numbers cannot be the same.');
        END IF;

        IF p_amount <= 0 THEN
            RAISE_APPLICATION_ERROR(-20004, 'Transfer amount must be greater than zero.');
        END IF;

        -- Create a savepoint
        SAVEPOINT sp_before_transfer;

        -- 2. Validate & lock sender account
        BEGIN
            SELECT balance INTO v_from_balance 
            FROM ACCOUNTS 
            WHERE account_no = p_from_acc AND status = 'ACTIVE' 
            FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20003, 'Sender account ' || p_from_acc || ' is inactive or invalid.');
        END;

        IF v_from_balance < p_amount THEN
            RAISE_APPLICATION_ERROR(-20002, 'Transfer failed! Insufficient balance in Account ' || p_from_acc || 
                                           '. Available: ₹' || v_from_balance);
        END IF;

        -- 3. Validate & lock receiver account
        BEGIN
            SELECT status INTO v_to_status 
            FROM ACCOUNTS 
            WHERE account_no = p_to_acc AND status = 'ACTIVE' 
            FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20003, 'Receiver account ' || p_to_acc || ' is inactive or invalid.');
        END;

        -- 4. Execute atomic debit and credit
        UPDATE ACCOUNTS 
        SET balance = balance - p_amount 
        WHERE account_no = p_from_acc;

        UPDATE ACCOUNTS 
        SET balance = balance + p_amount 
        WHERE account_no = p_to_acc;

        -- 5. Record Transaction Log
        INSERT INTO TRANSACTIONS (
            txn_id, from_account, to_account, txn_type, amount, status, remarks
        ) VALUES (
            SEQ_TXN_ID.NEXTVAL, p_from_acc, p_to_acc, 'TRANSFER', p_amount, 'SUCCESS', p_remarks
        );

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('✔ Transfer of ₹' || p_amount || ' successful from Acc: ' || 
                             p_from_acc || ' -> Acc: ' || p_to_acc);
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO sp_before_transfer;
            -- Also record the failed transaction attempt
            INSERT INTO TRANSACTIONS (
                txn_id, from_account, to_account, txn_type, amount, status, remarks
            ) VALUES (
                SEQ_TXN_ID.NEXTVAL, p_from_acc, p_to_acc, 'TRANSFER', p_amount, 'FAILED', 
                SUBSTR(SQLERRM, 1, 150)
            );
            COMMIT;
            DBMS_OUTPUT.PUT_LINE('✘ Fund transfer failed: ' || SQLERRM);
            RAISE;
    END transfer_funds;

    -- =================================================================
    -- PROCEDURE 5: Batch Monthly Interest using EXPLICIT CURSOR
    -- =================================================================
    PROCEDURE apply_monthly_interest(
        p_annual_rate IN NUMBER DEFAULT 4.0
    ) IS
        -- Explicit Cursor to fetch all active savings accounts
        CURSOR c_savings IS
            SELECT account_no, balance 
            FROM ACCOUNTS 
            WHERE account_type = 'SAVINGS' AND status = 'ACTIVE' AND balance > 0
            FOR UPDATE OF balance;

        v_acc_no      ACCOUNTS.account_no%TYPE;
        v_bal         ACCOUNTS.balance%TYPE;
        v_interest    NUMBER(12, 2);
        v_count       NUMBER := 0;
        v_total_paid  NUMBER := 0;
    BEGIN
        DBMS_OUTPUT.PUT_LINE('=====================================================');
        DBMS_OUTPUT.PUT_LINE('   APPLYING MONTHLY INTEREST (' || p_annual_rate || '% P.A.)');
        DBMS_OUTPUT.PUT_LINE('=====================================================');

        OPEN c_savings;
        LOOP
            FETCH c_savings INTO v_acc_no, v_bal;
            EXIT WHEN c_savings%NOTFOUND;

            -- Calculate 1 month interest: (Balance * Rate / 100) / 12
            v_interest := ROUND((v_bal * (p_annual_rate / 100)) / 12, 2);

            IF v_interest > 0 THEN
                -- Update account balance using CURRENT OF cursor
                UPDATE ACCOUNTS 
                SET balance = balance + v_interest 
                WHERE CURRENT OF c_savings;

                -- Record Interest transaction
                INSERT INTO TRANSACTIONS (
                    txn_id, to_account, txn_type, amount, status, remarks
                ) VALUES (
                    SEQ_TXN_ID.NEXTVAL, v_acc_no, 'INTEREST', v_interest, 'SUCCESS', 
                    'Monthly Interest @ ' || p_annual_rate || '%'
                );

                v_count := v_count + 1;
                v_total_paid := v_total_paid + v_interest;
                DBMS_OUTPUT.PUT_LINE('Acc ' || v_acc_no || ' credited with ₹' || v_interest);
            END IF;
        END LOOP;
        CLOSE c_savings;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('-----------------------------------------------------');
        DBMS_OUTPUT.PUT_LINE('Interest applied to ' || v_count || ' accounts. Total Interest Paid: ₹' || v_total_paid);
    EXCEPTION
        WHEN OTHERS THEN
            IF c_savings%ISOPEN THEN
                CLOSE c_savings;
            END IF;
            ROLLBACK;
            DBMS_OUTPUT.PUT_LINE('✘ Failed to apply monthly interest: ' || SQLERRM);
            RAISE;
    END apply_monthly_interest;

    -- =================================================================
    -- PROCEDURE 6: Print Mini-Statement using CURSOR & DBMS_OUTPUT
    -- =================================================================
    PROCEDURE print_mini_statement(
        p_account_no IN NUMBER,
        p_limit      IN NUMBER DEFAULT 5
    ) IS
        CURSOR c_txns IS
            SELECT txn_id, txn_type, amount, status, 
                   TO_CHAR(txn_date, 'YYYY-MM-DD HH24:MI') AS f_date, remarks
            FROM (
                SELECT * FROM TRANSACTIONS 
                WHERE from_account = p_account_no OR to_account = p_account_no
                ORDER BY txn_date DESC
            )
            WHERE ROWNUM <= p_limit;

        v_holder ACCOUNTS.holder_name%TYPE;
        v_bal    ACCOUNTS.balance%TYPE;
    BEGIN
        SELECT holder_name, balance INTO v_holder, v_bal 
        FROM ACCOUNTS 
        WHERE account_no = p_account_no;

        DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------------------');
        DBMS_OUTPUT.PUT_LINE('                        MINI STATEMENT');
        DBMS_OUTPUT.PUT_LINE(' Account No   : ' || p_account_no);
        DBMS_OUTPUT.PUT_LINE(' Account Holder: ' || v_holder);
        DBMS_OUTPUT.PUT_LINE(' Current Balance: ₹' || v_bal);
        DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------------------');
        DBMS_OUTPUT.PUT_LINE(RPAD('TXN ID', 10) || RPAD('TYPE', 12) || RPAD('AMOUNT', 12) || 
                             RPAD('STATUS', 10) || RPAD('DATE', 18) || 'REMARKS');
        DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------------------');

        FOR rec IN c_txns LOOP
            DBMS_OUTPUT.PUT_LINE(
                RPAD(rec.txn_id, 10) || 
                RPAD(rec.txn_type, 12) || 
                RPAD('₹' || rec.amount, 12) || 
                RPAD(rec.status, 10) || 
                RPAD(rec.f_date, 18) || 
                rec.remarks
            );
        END LOOP;
        DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------------------');
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('✘ Account ' || p_account_no || ' not found.');
    END print_mini_statement;

END BANKING_PKG;
/
