-- =====================================================
-- EXERCISE 1
-- =====================================================

SELECT *
FROM `sprint3_silver.transactions_clean` AS t
JOIN `sprint3_silver.companies_clean` AS c
    ON t.company_id = c.company_id
WHERE t.timestamp = '2022-03-12'
  AND country = 'Germany';


-- =====================================================
-- EXERCISE 2.1 - GENERATE RECENT DATA
-- =====================================================

CREATE OR REPLACE TABLE `sprint3_silver.transactions_recent`
AS
SELECT
    * EXCEPT(timestamp),
    TIMESTAMP_SUB(
        CURRENT_TIMESTAMP(),
        INTERVAL CAST(RAND() * 50 AS INT64) DAY
    ) AS timestamp
FROM `sprint3_silver.transactions_clean`;


-- =====================================================
-- EXERCISE 2.2 - PARTITIONING & CLUSTERING
-- =====================================================

CREATE OR REPLACE TABLE `sprint3_gold.fact_transactions_optimized`
PARTITION BY DATE(timestamp)
CLUSTER BY company_id
AS
SELECT *
FROM `sprint3_silver.transactions_recent`;


-- =====================================================
-- EXERCISE 3 - BENCHMARK
-- =====================================================

-- NON-OPTIMIZED

SELECT *
FROM `sprint3_silver.transactions_recent`
WHERE timestamp BETWEEN
    TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND CURRENT_TIMESTAMP();


-- OPTIMIZED

SELECT *
FROM `sprint3_gold.fact_transactions_optimized`
WHERE timestamp BETWEEN
    TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND CURRENT_TIMESTAMP();


-- =====================================================
-- EXERCISE 4 - MATERIALIZED VIEW
-- =====================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS `sprint3_gold.mv_daily_sales`
AS
SELECT
    DATE(timestamp) AS day,
    SUM(amount) AS total_sales
FROM `sprint3_gold.fact_transactions_optimized`
WHERE declined = 0
GROUP BY day;


-- =====================================================
-- LEVEL 2 - EXERCISE 1 - VIP CUSTOMERS
-- =====================================================

WITH VIP_Stats AS (
    SELECT
        user_id,
        SUM(amount) AS total_gastat,
        COUNT(*) AS num_compres,
        ROUND(AVG(amount), 2) AS tiquet_mig,
        MAX(amount) AS max_compra
    FROM `sprint3_silver.transactions_clean`
    WHERE declined = 0
    GROUP BY user_id
    HAVING total_gastat > 500
)

SELECT
    VIP_Stats.user_id,
    uc.name AS nom,
    uc.surname AS cognom,
    uc.email,
    num_compres,
    tiquet_mig,
    max_compra,
    total_gastat
FROM VIP_Stats
JOIN `sprint3_silver.users_combined` AS uc
    ON VIP_Stats.user_id = uc.user_id
ORDER BY total_gastat DESC;


-- =====================================================
-- LEVEL 2 - EXERCISE 2 - SALES TREND ANALYSIS
-- =====================================================

WITH tendencia_ventas AS (
    SELECT
        day,
        total_sales,
        LAG(total_sales) OVER (ORDER BY day) AS sales_yesterday
    FROM `sprint3_gold.mv_daily_sales`
)

SELECT
    day AS Data,
    total_sales AS Vendes_Avui,
    sales_yesterday AS Vendes_Ahir,
    ROUND(
        ((total_sales - sales_yesterday) / sales_yesterday) * 100,
        2
    ) AS Diff_Percentual
FROM tendencia_ventas
ORDER BY day;


-- =====================================================
-- LEVEL 2 - EXERCISE 4 - CUSTOMER LOYALTY
-- =====================================================

WITH TC1 AS (
    SELECT
        ROW_NUMBER() OVER (
            PARTITION BY tc.user_id
            ORDER BY tc.timestamp
        ) AS rn,
        tc.user_id,
        uc.name,
        uc.surname,
        uc.email,
        tc.amount,
        tc.timestamp
    FROM `sprint3_silver.transactions_clean` AS tc
    JOIN `sprint3_silver.users_combined` AS uc
        ON uc.user_id = tc.user_id
    WHERE declined = 0
    QUALIFY rn <= 3
),

TC2 AS (
    SELECT
        user_id,
        ROUND(AVG(amount), 2) AS avg
    FROM TC1
    GROUP BY user_id
)

SELECT
    TC1.user_id,
    name,
    surname,
    email,
    amount AS importe_3a_compra,
    DATE(timestamp) AS fecha_3a_compra,
    TC2.avg AS avg_first_3
FROM TC1
JOIN TC2
    ON TC1.user_id = TC2.user_id
WHERE rn = 3;


-- =====================================================
-- LEVEL 3 - EXERCISE 1 - FLATTEN TRANSACTIONS
-- =====================================================

CREATE OR REPLACE TABLE `sprint3_gold.dim_transactions_flat`
AS
SELECT
    transaction_id,
    DATE(timestamp) AS timestamp,
    amount AS total_ticket_GLOBAL,
    product_id,
    pr.name AS product_name,
    pr.price AS product_price
FROM `sprint3_silver.transactions_clean` AS tr
CROSS JOIN UNNEST(tr.product_ids) AS product_id
JOIN `sprint3_silver.products_clean` AS pr
    ON product_id = pr.product_id
WHERE tr.declined = 0
ORDER BY transaction_id;


-- =====================================================
-- LEVEL 3 - EXERCISE 2.1 - UDF
-- =====================================================

CREATE OR REPLACE FUNCTION sprint3_gold.calculate_tax(product_price FLOAT64)
RETURNS FLOAT64
AS (
    (product_price * 0.21) + product_price
);


-- =====================================================
-- LEVEL 3 - EXERCISE 2.2 - UDF INTEGRATION
-- =====================================================

CREATE OR REPLACE TABLE `sprint3_gold.dim_transactions_flat`
AS
SELECT
    transaction_id,
    DATE(timestamp) AS timestamp,
    amount AS total_ticket_GLOBAL,
    product_id,
    pr.name AS product_name,
    pr.price AS product_price,
    sprint3_gold.calculate_tax(pr.price) AS product_price_tax_inc
FROM `sprint3_silver.transactions_clean` AS tr
CROSS JOIN UNNEST(tr.product_ids) AS product_id
JOIN `sprint3_silver.products_clean` AS pr
    ON product_id = pr.product_id
WHERE tr.declined = 0
ORDER BY transaction_id;