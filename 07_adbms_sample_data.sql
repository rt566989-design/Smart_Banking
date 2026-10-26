-- =====================================================================
-- ADVANCED DATABASE MANAGEMENT SYSTEMS (ADBMS) & ORACLE PL/SQL
-- SMART BANKING & ENTERPRISE FUND TRANSFER SYSTEM
-- File: 07_adbms_sample_data.sql
-- Description: Seed Data for Branches, ORDBMS Customers, Accounts,
--              Partitioned Ledgers, and Multi-Quarter Transactions
-- =====================================================================

-- 1. SEED BRANCHES (Distributed Multi-Region Network)
INSERT INTO BRANCHES (branch_code, branch_name, city, region, ifsc_code) 
VALUES ('BR-DEL-01', 'Connaught Place Branch', 'New Delhi', 'NORTH', 'SMART0001001');

INSERT INTO BRANCHES (branch_code, branch_name, city, region, ifsc_code) 
VALUES ('BR-MUM-01', 'Nariman Point Branch', 'Mumbai', 'WEST', 'SMART0002001');

INSERT INTO BRANCHES (branch_code, branch_name, city, region, ifsc_code) 
VALUES ('BR-BLR-01', 'Indiranagar Tech Hub', 'Bengaluru', 'SOUTH', 'SMART0003001');

INSERT INTO BRANCHES (branch_code, branch_name, city, region, ifsc_code) 
VALUES ('BR-KOL-01', 'Park Street Branch', 'Kolkata', 'EAST', 'SMART0004001');

-- 2. SEED CUSTOMERS_OBJ USING OBJECT-RELATIONAL TYPES & VARRAYS
INSERT INTO CUSTOMERS_OBJ VALUES (
    1001,
    'Rahul Sharma',
    'rahul.sharma@example.com',
    PHONE_ARRAY_TYP('9876543210', '0112345678'),
    ADDRESS_TYP('12/A Barakhamba Road', 'New Delhi', 'Delhi', '110001'),
    KYC_DOC_TYP('AADHAAR', '4589-1234-9012', 'VERIFIED'),
    CURRENT_TIMESTAMP
);

INSERT INTO CUSTOMERS_OBJ VALUES (
    1002,
    'Priya Patel',
    'priya.patel@example.com',
    PHONE_ARRAY_TYP('9823456781', '0229876543'),
    ADDRESS_TYP('84 Marine Drive', 'Mumbai', 'Maharashtra', '400020'),
    KYC_DOC_TYP('PAN', 'ABCDE1234F', 'VERIFIED'),
    CURRENT_TIMESTAMP
);

INSERT INTO CUSTOMERS_OBJ VALUES (
    1003,
    'Amit Verma',
    'amit.verma@example.com',
    PHONE_ARRAY_TYP('9811223344'),
    ADDRESS_TYP('100 Feet Road, Indiranagar', 'Bengaluru', 'Karnataka', '560038'),
    KYC_DOC_TYP('PASSPORT', 'Z9876543', 'VERIFIED'),
    CURRENT_TIMESTAMP
);

INSERT INTO CUSTOMERS_OBJ VALUES (
    1004,
    'Neha Singh',
    'neha.singh@example.com',
    PHONE_ARRAY_TYP('9899887766'),
    ADDRESS_TYP('45 Civil Lines', 'New Delhi', 'Delhi', '110054'),
    KYC_DOC_TYP('AADHAAR', '8899-7711-2233', 'VERIFIED'),
    CURRENT_TIMESTAMP
);

INSERT INTO CUSTOMERS_OBJ VALUES (
    1005,
    'Vikram Malhotra',
    'vikram.m@example.com',
    PHONE_ARRAY_TYP('9833445566', '9833445567'),
    ADDRESS_TYP('17 Park Street', 'Kolkata', 'West Bengal', '700016'),
    KYC_DOC_TYP('PAN', 'XYZPM9988K', 'VERIFIED'),
    CURRENT_TIMESTAMP
);

INSERT INTO CUSTOMERS_OBJ VALUES (
    1006,
    'Ananya Iyer',
    'ananya.iyer@example.com',
    PHONE_ARRAY_TYP('9845012345'),
    ADDRESS_TYP('22 Koramangala 4th Block', 'Bengaluru', 'Karnataka', '560034'),
    KYC_DOC_TYP('AADHAAR', '3344-5566-7788', 'VERIFIED'),
    CURRENT_TIMESTAMP
);

-- 3. SEED ACCOUNTS & LIST-PARTITIONED ACCOUNTS
INSERT INTO ACCOUNTS (account_no, customer_id, branch_code, holder_name, email, phone, account_type, balance, daily_limit, status)
VALUES (1001, 1001, 'BR-DEL-01', 'Rahul Sharma', 'rahul.sharma@example.com', '9876543210', 'SAVINGS', 75000.00, 50000.00, 'ACTIVE');

INSERT INTO ACCOUNTS (account_no, customer_id, branch_code, holder_name, email, phone, account_type, balance, daily_limit, status)
VALUES (1002, 1002, 'BR-MUM-01', 'Priya Patel', 'priya.patel@example.com', '9823456781', 'SALARY', 120000.00, 75000.00, 'ACTIVE');

INSERT INTO ACCOUNTS (account_no, customer_id, branch_code, holder_name, email, phone, account_type, balance, daily_limit, status)
VALUES (1003, 1003, 'BR-BLR-01', 'Amit Verma', 'amit.verma@example.com', '9811223344', 'CURRENT', 250000.00, 150000.00, 'ACTIVE');

INSERT INTO ACCOUNTS (account_no, customer_id, branch_code, holder_name, email, phone, account_type, balance, daily_limit, status)
VALUES (1004, 1004, 'BR-DEL-01', 'Neha Singh', 'neha.singh@example.com', '9899887766', 'SAVINGS', 15000.00, 50000.00, 'ACTIVE');

INSERT INTO ACCOUNTS (account_no, customer_id, branch_code, holder_name, email, phone, account_type, balance, daily_limit, status)
VALUES (1005, 1005, 'BR-KOL-01', 'Vikram Malhotra', 'vikram.m@example.com', '9833445566', 'CURRENT', 680000.00, 200000.00, 'ACTIVE');

INSERT INTO ACCOUNTS (account_no, customer_id, branch_code, holder_name, email, phone, account_type, balance, daily_limit, status)
VALUES (1006, 1006, 'BR-BLR-01', 'Ananya Iyer', 'ananya.iyer@example.com', '9845012345', 'SAVINGS', 850.00, 25000.00, 'ACTIVE');

-- Populate ACCOUNTS_PARTITIONED
INSERT INTO ACCOUNTS_PARTITIONED (account_no, holder_name, branch_code, account_type, balance, status)
SELECT account_no, holder_name, branch_code, account_type, balance, status FROM ACCOUNTS;

-- 4. SEED HISTORICAL TRANSACTIONS SPANNING MULTIPLE PARTITIONS (Q1, Q2, Q3, Q4, Current)
-- Q1 2025 Partition (p_2025_q1)
INSERT INTO TRANSACTIONS (txn_id, to_account, txn_type, amount, txn_date, status, remarks)
VALUES (50001, 1001, 'DEPOSIT', 50000.00, TO_TIMESTAMP('2025-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS'), 'SUCCESS', 'Opening Deposit');

INSERT INTO TRANSACTIONS_PARTITIONED (txn_id, to_account, txn_type, amount, txn_date, status, remarks)
VALUES (50001, 1001, 'DEPOSIT', 50000.00, TO_DATE('2025-01-15', 'YYYY-MM-DD'), 'SUCCESS', 'Opening Deposit');

-- Q2 2025 Partition (p_2025_q2)
INSERT INTO TRANSACTIONS (txn_id, from_account, to_account, txn_type, amount, txn_date, status, remarks)
VALUES (50002, 1001, 1004, 'TRANSFER', 10000.00, TO_TIMESTAMP('2025-05-10 14:15:00', 'YYYY-MM-DD HH24:MI:SS'), 'SUCCESS', 'Family Allowance');

INSERT INTO TRANSACTIONS_PARTITIONED (txn_id, from_account, to_account, txn_type, amount, txn_date, status, remarks)
VALUES (50002, 1001, 1004, 'TRANSFER', 10000.00, TO_DATE('2025-05-10', 'YYYY-MM-DD'), 'SUCCESS', 'Family Allowance');

-- Q3 2025 Partition (p_2025_q3)
INSERT INTO TRANSACTIONS (txn_id, to_account, txn_type, amount, txn_date, status, remarks)
VALUES (50003, 1002, 'DEPOSIT', 120000.00, TO_TIMESTAMP('2025-08-01 09:00:00', 'YYYY-MM-DD HH24:MI:SS'), 'SUCCESS', 'Corporate Salary Credit');

INSERT INTO TRANSACTIONS_PARTITIONED (txn_id, to_account, txn_type, amount, txn_date, status, remarks)
VALUES (50003, 1002, 'DEPOSIT', 120000.00, TO_DATE('2025-08-01', 'YYYY-MM-DD'), 'SUCCESS', 'Corporate Salary Credit');

-- Q4 2025 Partition (p_2025_q4)
INSERT INTO TRANSACTIONS (txn_id, from_account, to_account, txn_type, amount, txn_date, status, remarks)
VALUES (50004, 1003, 1005, 'TRANSFER', 45000.00, TO_TIMESTAMP('2025-11-20 16:45:00', 'YYYY-MM-DD HH24:MI:SS'), 'SUCCESS', 'B2B Vendor Invoice Settlement');

INSERT INTO TRANSACTIONS_PARTITIONED (txn_id, from_account, to_account, txn_type, amount, txn_date, status, remarks)
VALUES (50004, 1003, 1005, 'TRANSFER', 45000.00, TO_DATE('2025-11-20', 'YYYY-MM-DD'), 'SUCCESS', 'B2B Vendor Invoice Settlement');

-- Current Date Transactions
INSERT INTO TRANSACTIONS (txn_id, to_account, txn_type, amount, txn_date, status, remarks)
VALUES (50005, 1001, 'DEPOSIT', 35000.00, CURRENT_TIMESTAMP, 'SUCCESS', 'UPI Inward Credit');

INSERT INTO TRANSACTIONS_PARTITIONED (txn_id, to_account, txn_type, amount, txn_date, status, remarks)
VALUES (50005, 1001, 'DEPOSIT', 35000.00, TRUNC(SYSDATE), 'SUCCESS', 'UPI Inward Credit');

COMMIT;

-- Refresh Materialized Views with initial seed dataset
BEGIN
    DBMS_MVIEW.REFRESH('MV_DAILY_BRANCH_SUMMARY', 'C');
    DBMS_MVIEW.REFRESH('MV_CUSTOMER_NETWORTH', 'C');
    DBMS_OUTPUT.PUT_LINE('✔ Seed data populated & Materialized Views initialized!');
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('ℹ Materialized views refreshed or skipped.');
END;
/
