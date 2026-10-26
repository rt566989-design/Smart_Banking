-- =====================================================================
-- SMART BANKING & FUND TRANSFER SYSTEM (ALL-IN-ONE SCRIPT)
-- Description: Complete PL/SQL Mini Project in a single executable file.
-- How to run: Open Oracle Live SQL (livesql.oracle.com) or Oracle SQL Developer,
--             paste this entire code and press Run (F5).
-- =====================================================================

SET SERVEROUTPUT ON SIZE 1000000;

-- ---------------------------------------------------------------------
-- STEP 1: DROP OLD OBJECTS (CLEAN START)
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- STEP 2: CREATE SEQUENCES
-- ---------------------------------------------------------------------
CREATE SEQUENCE SEQ_ACC_NO START WITH 1001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_TXN_ID START WITH 50001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_LOG_ID START WITH 1 INCREMENT BY 1 NOCACHE;

-- ---------------------------------------------------------------------
-- STEP 3: CREATE TABLES & CONSTRAINTS
-- ---------------------------------------------------------------------
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

CREATE TABLE AUDIT_LOGS (
    log_id           NUMBER(12) PRIMARY KEY,
    account_no       NUMBER(10) NOT NULL,
    action_type      VARCHAR2(30) NOT NULL,
    old_balance      NUMBER(12, 2),
    new_balance      NUMBER(12, 2),
    changed_by       VARCHAR2(50) DEFAULT USER,
    changed_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- STEP 4: TRIGGERS (AUDITING & BUSINESS VALIDATIONS)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_ACCOUNT_AUDIT
AFTER UPDATE OF balance, status ON ACCOUNTS
FOR EACH ROW
DECLARE
    v_action VARCHAR2(30);
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
        v_action := 'ACCOUNT_MODIFIED';
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
            '. Account still has an active balance of ₹' || :OLD.balance || 
            '. Please withdraw/transfer funds first.'
        );
    END IF;
END;
/

-- ---------------------------------------------------------------------
-- STEP 5: PACKAGE SPECIFICATION (BANKING_PKG)
-- ---------------------------------------------------------------------
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

    PROCEDURE open_account(
        p_name            IN  VARCHAR2,
        p_email           IN  VARCHAR2,
        p_phone           IN  VARCHAR2,
        p_type            IN  VARCHAR2,
        p_initial_deposit IN  NUMBER,
        p_account_no      OUT NUMBER
    );

    PROCEDURE deposit(
        p_account_no IN NUMBER,
        p_amount     IN NUMBER,
        p_remarks    IN VARCHAR2 DEFAULT 'Cash Deposit'
    );

    PROCEDURE withdraw(
        p_account_no IN NUMBER,
        p_amount     IN NUMBER,
        p_remarks    IN VARCHAR2 DEFAULT 'Cash Withdrawal'
    );

    PROCEDURE transfer_funds(
        p_from_acc IN NUMBER,
        p_to_acc   IN NUMBER,
        p_amount   IN NUMBER,
        p_remarks  IN VARCHAR2 DEFAULT 'Fund Transfer'
    );

    PROCEDURE apply_monthly_interest(
        p_annual_rate IN NUMBER DEFAULT 4.0
    );

    PROCEDURE print_mini_statement(
        p_account_no IN NUMBER,
        p_limit      IN NUMBER DEFAULT 5
    );

    FUNCTION get_balance(p_account_no IN NUMBER) RETURN NUMBER;
    FUNCTION is_account_active(p_account_no IN NUMBER) RETURN BOOLEAN;
    FUNCTION calculate_monthly_interest(
        p_account_no  IN NUMBER, 
        p_annual_rate IN NUMBER DEFAULT 4.0
    ) RETURN NUMBER;
END BANKING_PKG;
/

-- ---------------------------------------------------------------------
-- STEP 6: PACKAGE BODY (BANKING_PKG)
-- ---------------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY BANKING_PKG AS

    FUNCTION is_account_active(p_account_no IN NUMBER) RETURN BOOLEAN IS
        v_status ACCOUNTS.status%TYPE;
    BEGIN
        SELECT status INTO v_status FROM ACCOUNTS WHERE account_no = p_account_no;
        RETURN (v_status = 'ACTIVE');
    EXCEPTION
        WHEN NO_DATA_FOUND THEN 
            RETURN FALSE;
    END is_account_active;

    FUNCTION get_balance(p_account_no IN NUMBER) RETURN NUMBER IS
        v_balance ACCOUNTS.balance%TYPE;
    BEGIN
        SELECT balance INTO v_balance FROM ACCOUNTS WHERE account_no = p_account_no;
        RETURN v_balance;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20006, 'Account number ' || p_account_no || ' does not exist.');
    END get_balance;

    FUNCTION calculate_monthly_interest(
        p_account_no  IN NUMBER, 
        p_annual_rate IN NUMBER DEFAULT 4.0
    ) RETURN NUMBER IS
        v_balance NUMBER;
    BEGIN
        v_balance := get_balance(p_account_no);
        RETURN ROUND(v_balance * (p_annual_rate / 100) / 12, 2);
    END calculate_monthly_interest;

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

        IF p_initial_deposit > 0 THEN
            INSERT INTO TRANSACTIONS (
                txn_id, to_account, txn_type, amount, status, remarks
            ) VALUES (
                SEQ_TXN_ID.NEXTVAL, p_account_no, 'DEPOSIT', p_initial_deposit, 'SUCCESS', 'Opening Deposit'
            );
        END IF;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('✔ Account created: ' || p_account_no || ' (' || p_name || ')');
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END open_account;

    PROCEDURE deposit(
        p_account_no IN NUMBER,
        p_amount     IN NUMBER,
        p_remarks    IN VARCHAR2 DEFAULT 'Cash Deposit'
    ) IS
    BEGIN
        IF p_amount <= 0 THEN
            RAISE_APPLICATION_ERROR(-20004, 'Deposit amount must be > 0.');
        END IF;

        IF NOT is_account_active(p_account_no) THEN
            RAISE_APPLICATION_ERROR(-20003, 'Account is inactive or not found.');
        END IF;

        UPDATE ACCOUNTS SET balance = balance + p_amount WHERE account_no = p_account_no;

        INSERT INTO TRANSACTIONS (
            txn_id, to_account, txn_type, amount, status, remarks
        ) VALUES (
            SEQ_TXN_ID.NEXTVAL, p_account_no, 'DEPOSIT', p_amount, 'SUCCESS', p_remarks
        );

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('✔ Deposited ₹' || p_amount || ' to Acc ' || p_account_no || 
                             ' | New Balance: ₹' || get_balance(p_account_no));
    END deposit;

    PROCEDURE withdraw(
        p_account_no IN NUMBER,
        p_amount     IN NUMBER,
        p_remarks    IN VARCHAR2 DEFAULT 'Cash Withdrawal'
    ) IS
        v_current_balance NUMBER;
    BEGIN
        IF p_amount <= 0 THEN
            RAISE_APPLICATION_ERROR(-20004, 'Withdrawal amount must be > 0.');
        END IF;

        IF NOT is_account_active(p_account_no) THEN
            RAISE_APPLICATION_ERROR(-20003, 'Account is not active.');
        END IF;

        SELECT balance INTO v_current_balance FROM ACCOUNTS WHERE account_no = p_account_no FOR UPDATE;

        IF v_current_balance < p_amount THEN
            RAISE_APPLICATION_ERROR(-20002, 'Insufficient balance. Available: ₹' || v_current_balance || 
                                           ', Requested: ₹' || p_amount);
        END IF;

        UPDATE ACCOUNTS SET balance = balance - p_amount WHERE account_no = p_account_no;

        INSERT INTO TRANSACTIONS (
            txn_id, from_account, txn_type, amount, status, remarks
        ) VALUES (
            SEQ_TXN_ID.NEXTVAL, p_account_no, 'WITHDRAWAL', p_amount, 'SUCCESS', p_remarks
        );

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('✔ Withdrawn ₹' || p_amount || ' from Acc ' || p_account_no || 
                             ' | Remaining Balance: ₹' || (v_current_balance - p_amount));
    END withdraw;

    PROCEDURE transfer_funds(
        p_from_acc IN NUMBER,
        p_to_acc   IN NUMBER,
        p_amount   IN NUMBER,
        p_remarks  IN VARCHAR2 DEFAULT 'Fund Transfer'
    ) IS
        v_from_balance NUMBER;
        v_to_status    ACCOUNTS.status%TYPE;
    BEGIN
        IF p_from_acc = p_to_acc THEN
            RAISE_APPLICATION_ERROR(-20005, 'Sender and Receiver account numbers cannot be the same.');
        END IF;
        IF p_amount <= 0 THEN
            RAISE_APPLICATION_ERROR(-20004, 'Transfer amount must be > 0.');
        END IF;

        SAVEPOINT sp_before_transfer;

        BEGIN
            SELECT balance INTO v_from_balance FROM ACCOUNTS WHERE account_no = p_from_acc AND status = 'ACTIVE' FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20003, 'Sender account is invalid or inactive.');
        END;

        IF v_from_balance < p_amount THEN
            RAISE_APPLICATION_ERROR(-20002, 'Insufficient funds in sender account.');
        END IF;

        BEGIN
            SELECT status INTO v_to_status FROM ACCOUNTS WHERE account_no = p_to_acc AND status = 'ACTIVE' FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20003, 'Receiver account is invalid or inactive.');
        END;

        UPDATE ACCOUNTS SET balance = balance - p_amount WHERE account_no = p_from_acc;
        UPDATE ACCOUNTS SET balance = balance + p_amount WHERE account_no = p_to_acc;

        INSERT INTO TRANSACTIONS (
            txn_id, from_account, to_account, txn_type, amount, status, remarks
        ) VALUES (
            SEQ_TXN_ID.NEXTVAL, p_from_acc, p_to_acc, 'TRANSFER', p_amount, 'SUCCESS', p_remarks
        );

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('✔ Transferred ₹' || p_amount || ' from Acc ' || p_from_acc || ' to Acc ' || p_to_acc);
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO sp_before_transfer;
            INSERT INTO TRANSACTIONS (
                txn_id, from_account, to_account, txn_type, amount, status, remarks
            ) VALUES (
                SEQ_TXN_ID.NEXTVAL, p_from_acc, p_to_acc, 'TRANSFER', p_amount, 'FAILED', SUBSTR(SQLERRM, 1, 150)
            );
            COMMIT;
            RAISE;
    END transfer_funds;

    PROCEDURE apply_monthly_interest(
        p_annual_rate IN NUMBER DEFAULT 4.0
    ) IS
        CURSOR c_savings IS
            SELECT account_no, balance FROM ACCOUNTS 
            WHERE account_type = 'SAVINGS' AND status = 'ACTIVE' AND balance > 0
            FOR UPDATE OF balance;

        v_acc_no     ACCOUNTS.account_no%TYPE;
        v_bal        ACCOUNTS.balance%TYPE;
        v_interest   NUMBER(12, 2);
        v_count      NUMBER := 0;
        v_total_paid NUMBER := 0;
    BEGIN
        DBMS_OUTPUT.PUT_LINE('=====================================================');
        DBMS_OUTPUT.PUT_LINE('   APPLYING MONTHLY INTEREST (' || p_annual_rate || '% P.A.)');
        DBMS_OUTPUT.PUT_LINE('=====================================================');
        OPEN c_savings;
        LOOP
            FETCH c_savings INTO v_acc_no, v_bal;
            EXIT WHEN c_savings%NOTFOUND;

            v_interest := ROUND((v_bal * (p_annual_rate / 100)) / 12, 2);
            IF v_interest > 0 THEN
                UPDATE ACCOUNTS SET balance = balance + v_interest WHERE CURRENT OF c_savings;

                INSERT INTO TRANSACTIONS (
                    txn_id, to_account, txn_type, amount, status, remarks
                ) VALUES (
                    SEQ_TXN_ID.NEXTVAL, v_acc_no, 'INTEREST', v_interest, 'SUCCESS', 'Interest @ ' || p_annual_rate || '%'
                );

                v_count := v_count + 1;
                v_total_paid := v_total_paid + v_interest;
                DBMS_OUTPUT.PUT_LINE('Acc ' || v_acc_no || ' earned interest: ₹' || v_interest);
            END IF;
        END LOOP;
        CLOSE c_savings;
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('-----------------------------------------------------');
        DBMS_OUTPUT.PUT_LINE('Interest credited to ' || v_count || ' accounts. Total: ₹' || v_total_paid);
    END apply_monthly_interest;

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
            ) WHERE ROWNUM <= p_limit;

        v_holder ACCOUNTS.holder_name%TYPE;
        v_bal    ACCOUNTS.balance%TYPE;
    BEGIN
        SELECT holder_name, balance INTO v_holder, v_bal FROM ACCOUNTS WHERE account_no = p_account_no;

        DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------------------');
        DBMS_OUTPUT.PUT_LINE('MINI STATEMENT | Acc: ' || p_account_no || ' (' || v_holder || ') | Balance: ₹' || v_bal);
        DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------------------');
        DBMS_OUTPUT.PUT_LINE(RPAD('TXN ID', 10) || RPAD('TYPE', 12) || RPAD('AMOUNT', 12) || RPAD('STATUS', 10) || 'REMARKS');
        DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------------------');

        FOR rec IN c_txns LOOP
            DBMS_OUTPUT.PUT_LINE(
                RPAD(rec.txn_id, 10) || 
                RPAD(rec.txn_type, 12) || 
                RPAD('₹' || rec.amount, 12) || 
                RPAD(rec.status, 10) || 
                rec.remarks
            );
        END LOOP;
        DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------------------');
    END print_mini_statement;

END BANKING_PKG;
/

-- ---------------------------------------------------------------------
-- STEP 7: SEED SAMPLE ACCOUNTS
-- ---------------------------------------------------------------------
DECLARE
    v1 NUMBER; v2 NUMBER; v3 NUMBER; v4 NUMBER;
BEGIN
    BANKING_PKG.open_account('Rahul Sharma', 'rahul@example.com', '9876543210', 'SAVINGS', 25000, v1);
    BANKING_PKG.open_account('Priya Patel', 'priya@example.com', '9823456781', 'SALARY', 50000, v2);
    BANKING_PKG.open_account('Amit Verma', 'amit@example.com', '9811223344', 'CURRENT', 100000, v3);
    BANKING_PKG.open_account('Neha Singh', 'neha@example.com', '9899887766', 'SAVINGS', 1500, v4);
END;
/

-- ---------------------------------------------------------------------
-- STEP 8: RUN TEST TRANSACTIONS & EXCEPTION TESTS
-- ---------------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- 1. Testing Deposit & Withdraw ---');
    BANKING_PKG.deposit(1001, 5000, 'Cash Deposit via CDM');
    BANKING_PKG.withdraw(1002, 2000, 'ATM Withdrawal');

    DBMS_OUTPUT.PUT_LINE('--- 2. Testing Fund Transfer ---');
    BANKING_PKG.transfer_funds(1001, 1002, 3000, 'Rent payment');

    DBMS_OUTPUT.PUT_LINE('--- 3. Testing Insufficient Balance Exception Handling ---');
    BEGIN
        BANKING_PKG.transfer_funds(1004, 1001, 50000, 'Overdraw attempt');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Expected Error caught: ' || SQLERRM);
    END;
    
    DBMS_OUTPUT.PUT_LINE('--- 4. Batch Monthly Interest via Cursor ---');
    BANKING_PKG.apply_monthly_interest(4.5);

    DBMS_OUTPUT.PUT_LINE('--- 5. Mini Statements ---');
    BANKING_PKG.print_mini_statement(1001, 5);
    BANKING_PKG.print_mini_statement(1002, 5);
END;
/

-- ---------------------------------------------------------------------
-- STEP 9: VIEW AUTOMATED AUDIT TRAIL LOGS
-- ---------------------------------------------------------------------
SELECT log_id, account_no, action_type, old_balance, new_balance, changed_by, changed_at 
FROM AUDIT_LOGS 
ORDER BY log_id;