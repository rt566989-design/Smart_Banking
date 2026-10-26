-- =====================================================================
-- ADVANCED DATABASE MANAGEMENT SYSTEMS (ADBMS) & ORACLE PL/SQL
-- SMART BANKING & ENTERPRISE FUND TRANSFER SYSTEM
-- File: 02_adbms_indexing_mviews.sql
-- Concepts Demonstrated:
--   1. Advanced Indexing: B-Tree, Bitmap, Function-Based, & Composite Indexes
--   2. Materialized View Logs (Change Data Capture for MVs)
--   3. Materialized Views with Fast Refresh on Demand
--   4. Execution Plan (EXPLAIN PLAN) for Query Optimization
-- =====================================================================

-- Clean up existing Materialized Views and Indexes
BEGIN
    EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW MV_DAILY_BRANCH_SUMMARY';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW MV_CUSTOMER_NETWORTH';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

-- =====================================================================
-- SECTION 1: ADVANCED INDEXING STRATEGIES
-- =====================================================================

-- 1.1 Bitmap Index on Low-Cardinality Columns (Classic ADBMS Concept)
-- NOTE: Bitmap indexes are ideal for read-heavy OLAP & columns with few distinct values
CREATE BITMAP INDEX IDX_ACC_STATUS_BMP ON ACCOUNTS(status);
CREATE BITMAP INDEX IDX_ACC_TYPE_BMP ON ACCOUNTS(account_type);
CREATE BITMAP INDEX IDX_TXN_TYPE_BMP ON TRANSACTIONS(txn_type);

-- 1.2 Function-Based Index (FBI)
-- Optimizes case-insensitive searches: WHERE UPPER(holder_name) = 'RAHUL SHARMA'
CREATE INDEX IDX_ACC_NAME_UPPER ON ACCOUNTS(UPPER(holder_name));

-- Optimizes date-truncated queries without time component
CREATE INDEX IDX_TXN_TRUNC_DATE ON TRANSACTIONS(TRUNC(CAST(txn_date AS DATE)));

-- 1.3 Composite Index
-- Optimizes statement lookup for a given account sorted descending by date
CREATE INDEX IDX_TXN_ACC_DATE ON TRANSACTIONS(from_account, txn_date DESC);
CREATE INDEX IDX_TXN_TO_DATE ON TRANSACTIONS(to_account, txn_date DESC);

-- 1.4 Local Partitioned Index on Range-Partitioned Transactions table
CREATE INDEX IDX_TXN_PART_DATE ON TRANSACTIONS_PARTITIONED(txn_date) LOCAL;

-- =====================================================================
-- SECTION 2: MATERIALIZED VIEW LOGS & MATERIALIZED VIEWS (OLAP)
-- =====================================================================

-- 2.1 Materialized View Log on ACCOUNTS to support Fast Refresh
CREATE MATERIALIZED VIEW LOG ON ACCOUNTS
WITH ROWID, SEQUENCE (account_no, branch_code, balance, status, account_type)
INCLUDING NEW VALUES;

-- 2.2 Materialized View Log on TRANSACTIONS
CREATE MATERIALIZED VIEW LOG ON TRANSACTIONS
WITH ROWID, SEQUENCE (txn_id, from_account, to_account, txn_type, amount, status)
INCLUDING NEW VALUES;

-- 2.3 Materialized View 1: MV_DAILY_BRANCH_SUMMARY
-- Pre-aggregates total deposits, liquidity, and active account count per branch
CREATE MATERIALIZED VIEW MV_DAILY_BRANCH_SUMMARY
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS
SELECT 
    b.branch_code,
    b.branch_name,
    b.region,
    COUNT(a.account_no)           AS total_accounts,
    NVL(SUM(a.balance), 0)        AS total_branch_liquidity,
    ROUND(NVL(AVG(a.balance), 0), 2) AS avg_account_balance,
    MAX(a.balance)                AS highest_account_balance
FROM BRANCHES b
LEFT JOIN ACCOUNTS a ON b.branch_code = a.branch_code AND a.status = 'ACTIVE'
GROUP BY b.branch_code, b.branch_name, b.region;

-- 2.4 Materialized View 2: MV_CUSTOMER_NETWORTH
-- Pre-aggregates customer financial exposure
CREATE MATERIALIZED VIEW MV_CUSTOMER_NETWORTH
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS
SELECT 
    a.holder_name,
    a.email,
    COUNT(a.account_no)   AS num_accounts,
    SUM(a.balance)        AS total_networth,
    CASE 
        WHEN SUM(a.balance) >= 500000 THEN 'HIGH NET WORTH (HNW)'
        WHEN SUM(a.balance) >= 100000 THEN 'PREMIUM RETAIL'
        ELSE 'STANDARD RETAIL'
    END                   AS client_tier
FROM ACCOUNTS a
GROUP BY a.holder_name, a.email;

-- =====================================================================
-- SECTION 3: REFRESH PROCEDURE FOR MATERIALIZED VIEWS
-- =====================================================================
CREATE OR REPLACE PROCEDURE REFRESH_ALL_MVIEWS AS
BEGIN
    DBMS_MVIEW.REFRESH('MV_DAILY_BRANCH_SUMMARY', 'C');
    DBMS_MVIEW.REFRESH('MV_CUSTOMER_NETWORTH', 'C');
    DBMS_OUTPUT.PUT_LINE('✔ All Banking Materialized Views successfully refreshed!');
END;
/

-- =====================================================================
-- SECTION 4: EXPLAIN PLAN VERIFICATION SCRIPT
-- =====================================================================
-- Shows cost optimizer utilizing the Function-Based Index:
EXPLAIN PLAN FOR 
SELECT * FROM ACCOUNTS WHERE UPPER(holder_name) = 'RAHUL SHARMA';

-- Query the execution plan (Run in SQL Developer to view plan table):
-- SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
