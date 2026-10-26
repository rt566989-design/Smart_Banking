-- =====================================================================
-- ADVANCED DATABASE MANAGEMENT SYSTEMS (ADBMS) & ORACLE PL/SQL
-- SMART BANKING & ENTERPRISE FUND TRANSFER SYSTEM
-- File: 06_adbms_olap_analytics.sql
-- Concepts Demonstrated:
--   1. OLAP Window & Analytical Functions (RANK, DENSE_RANK, ROW_NUMBER)
--   2. Running Balances & Moving Averages (ROWS BETWEEN clause)
--   3. Transaction Velocity / Anomaly Detection using LEAD() and LAG()
--   4. Multi-Dimensional Aggregations (ROLLUP, CUBE, GROUPING SETS)
--   5. Partition Pruning Queries for High-Volume Data Warehouses
-- =====================================================================

SET LINESIZE 200;
SET PAGESIZE 100;

-- =====================================================================
-- QUERY 1: CUSTOMER WEALTH RANKING (RANK & DENSE_RANK BY REGION)
-- =====================================================================
-- Evaluates high-net-worth customers across branches and regions
SELECT 
    b.region,
    b.branch_name,
    a.account_no,
    a.holder_name,
    a.account_type,
    a.balance,
    RANK() OVER (PARTITION BY b.region ORDER BY a.balance DESC)       AS regional_rank,
    DENSE_RANK() OVER (PARTITION BY b.region ORDER BY a.balance DESC) AS regional_dense_rank,
    PERCENT_RANK() OVER (ORDER BY a.balance)                          AS global_wealth_percentile
FROM ACCOUNTS a
JOIN BRANCHES b ON a.branch_code = b.branch_code
WHERE a.status = 'ACTIVE'
ORDER BY b.region, regional_rank;

-- =====================================================================
-- QUERY 2: RUNNING RUN-TIME BALANCE (WINDOW FRAME CLAUSE)
-- =====================================================================
-- Reconstructs the exact historical running balance after each transaction
SELECT 
    t.txn_id,
    t.txn_date,
    t.from_account,
    t.to_account,
    t.txn_type,
    t.amount,
    -- Compute cumulative net flow for a given account (e.g. Account 1001)
    SUM(CASE 
            WHEN t.to_account = 1001 THEN t.amount 
            WHEN t.from_account = 1001 THEN -t.amount 
            ELSE 0 
        END) OVER (
            ORDER BY t.txn_id 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_net_flow,
    -- 3-transaction moving average of transfer amounts
    ROUND(AVG(t.amount) OVER (
        ORDER BY t.txn_id 
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2) AS moving_avg_3_txns
FROM TRANSACTIONS t
WHERE t.from_account = 1001 OR t.to_account = 1001
ORDER BY t.txn_id;

-- =====================================================================
-- QUERY 3: TRANSACTION VELOCITY & RAPID WITHDRAWAL ANOMALY DETECTION
-- (USING LEAD() AND LAG())
-- =====================================================================
-- Detects suspicious velocity where two transactions occur in rapid succession
SELECT 
    txn_id,
    from_account,
    amount,
    txn_date,
    LAG(amount, 1) OVER (PARTITION BY from_account ORDER BY txn_date)   AS prev_txn_amount,
    LAG(txn_date, 1) OVER (PARTITION BY from_account ORDER BY txn_date) AS prev_txn_time,
    ROUND((CAST(txn_date AS DATE) - CAST(LAG(txn_date, 1) OVER (PARTITION BY from_account ORDER BY txn_date) AS DATE)) * 24 * 60, 2) AS minutes_since_last_txn
FROM TRANSACTIONS
WHERE from_account IS NOT NULL
ORDER BY from_account, txn_date;

-- =====================================================================
-- QUERY 4: MULTI-DIMENSIONAL AGGREGATIONS USING ROLLUP
-- =====================================================================
-- Generates subtotals by Region -> Branch -> Account Type and Grand Total
SELECT 
    NVL(b.region, '--- ALL REGIONS ---')           AS region,
    NVL(b.branch_name, '--- ALL BRANCHES ---')     AS branch,
    NVL(a.account_type, '--- ALL ACCOUNT TYPES ---') AS account_type,
    COUNT(a.account_no)                            AS total_accounts,
    SUM(a.balance)                                 AS total_deposits
FROM BRANCHES b
JOIN ACCOUNTS a ON b.branch_code = a.branch_code
GROUP BY ROLLUP(b.region, b.branch_name, a.account_type);

-- =====================================================================
-- QUERY 5: MULTI-DIMENSIONAL CUBE (CROSS-DIMENSIONAL ANALYSIS)
-- =====================================================================
-- Analyzes transaction totals across all combinations of Region and Txn Type
SELECT 
    NVL(b.region, 'ALL REGIONS')       AS region,
    NVL(t.txn_type, 'ALL TYPES')       AS txn_type,
    COUNT(t.txn_id)                    AS txn_count,
    SUM(t.amount)                      AS total_turnover,
    GROUPING(b.region)                 AS is_region_subtotal,
    GROUPING(t.txn_type)               AS is_type_subtotal
FROM TRANSACTIONS t
JOIN ACCOUNTS a ON (t.from_account = a.account_no OR t.to_account = a.account_no)
JOIN BRANCHES b ON a.branch_code = b.branch_code
GROUP BY CUBE(b.region, t.txn_type);

-- =====================================================================
-- QUERY 6: ADBMS PARTITION PRUNING DEMONSTRATION
-- =====================================================================
-- In an execution plan, Oracle will only scan partition P_2025_Q2 instead
-- of the entire table!
EXPLAIN PLAN FOR
SELECT * 
FROM TRANSACTIONS_PARTITIONED
WHERE txn_date BETWEEN TO_DATE('2025-04-15', 'YYYY-MM-DD') 
                   AND TO_DATE('2025-05-15', 'YYYY-MM-DD');

-- Run this to view the Partition Start and Stop numbers (Partition Pruning):
-- SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +PARTITION'));
