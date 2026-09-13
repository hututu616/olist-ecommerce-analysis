/* 1. 建库、建表 */
create database olist_ecommerce;
use olist_ecommerce;

SELECT DATABASE();
/* 1.1 客户表
   customer_id：更接近订单层面的客户记录
   customer_unique_id：识别同一个真实消费者
*/
CREATE TABLE customers (
    customer_id CHAR(32) PRIMARY KEY,
    customer_unique_id CHAR(32) NOT NULL,
    customer_zip_code_prefix INT,
    customer_city VARCHAR(64),
    customer_state CHAR(2)
);

/* 1.2 商品表 */
CREATE INDEX idx_customer_unique_id
ON customers(customer_unique_id);
CREATE TABLE products (
    product_id CHAR(32) PRIMARY KEY,
    product_category_name VARCHAR(64),
    product_name_lenghth INT,
    product_description_lenghth INT,
    product_photos_qty INT,
    product_weight_g INT,
    product_length_cm INT,
    product_height_cm INT,
    product_width_cm INT
);

/* 1.3 卖家表 */
CREATE TABLE sellers (
    seller_id CHAR(32) PRIMARY KEY,
    seller_zip_code_prefix INT,
    seller_city VARCHAR(64),
    seller_state CHAR(2)
);

/* 1.4 商品品类英文翻译表 */
CREATE TABLE category_translation (
    product_category_name VARCHAR(64) PRIMARY KEY,
    product_category_name_english VARCHAR(64)
);
/* 1.5 订单表 */
CREATE TABLE orders (
    order_id CHAR(32) PRIMARY KEY,
    customer_id CHAR(32) NOT NULL,
    order_status VARCHAR(20),
    order_purchase_timestamp DATETIME,
    order_approved_at DATETIME,
    order_delivered_carrier_date DATETIME,
    order_delivered_customer_date DATETIME,
    order_estimated_delivery_date DATETIME,
    CONSTRAINT fk_orders_customer
        FOREIGN KEY (customer_id)
        REFERENCES customers(customer_id)
);

/* 1.6 订单商品表 */
CREATE TABLE order_items (
    order_id CHAR(32),
    order_item_id INT,
    product_id CHAR(32),
    seller_id CHAR(32),
    shipping_limit_date DATETIME,
    price DECIMAL(10,2),
    freight_value DECIMAL(10,2),
    PRIMARY KEY (order_id, order_item_id),
    CONSTRAINT fk_items_order
        FOREIGN KEY (order_id)
        REFERENCES orders(order_id),
    CONSTRAINT fk_items_product
        FOREIGN KEY (product_id)
        REFERENCES products(product_id),
    CONSTRAINT fk_items_seller
        FOREIGN KEY (seller_id)
        REFERENCES sellers(seller_id)
);

/* 1.7 支付表 */
CREATE TABLE payments (
    order_id CHAR(32),
    payment_sequential INT,
    payment_type VARCHAR(20),
    payment_installments INT,
    payment_value DECIMAL(12,2),
    PRIMARY KEY (order_id, payment_sequential),
    CONSTRAINT fk_payments_order
        FOREIGN KEY (order_id)
        REFERENCES orders(order_id)
);

/* 1.8 评论表 */
CREATE TABLE reviews (
    review_id CHAR(32),
    order_id CHAR(32),
    review_score TINYINT,
    review_comment_title VARCHAR(255),
    review_comment_message TEXT,
    review_creation_date DATETIME,
    review_answer_timestamp DATETIME,
    PRIMARY KEY (review_id, order_id),
    CONSTRAINT fk_reviews_order
        FOREIGN KEY (order_id)
        REFERENCES orders(order_id)
);

/* 2. 基础数据检查 */
SELECT 'customers' AS table_name, COUNT(*) AS row_count
FROM customers

UNION ALL

SELECT 'orders', COUNT(*)
FROM orders

UNION ALL

SELECT 'order_items', COUNT(*)
FROM order_items

UNION ALL

SELECT 'payments', COUNT(*)
FROM payments

UNION ALL

SELECT 'reviews', COUNT(*)
FROM reviews

UNION ALL

SELECT 'products', COUNT(*)
FROM products

UNION ALL

SELECT 'sellers', COUNT(*)
FROM sellers

UNION ALL

SELECT 'category_translation', COUNT(*)
FROM category_translation;

SELECT COUNT(*)
FROM category_translation;

SELECT COUNT(*)
FROM order_items;

SELECT COUNT(*)
FROM reviews;

/* 3. 构建安全的订单级分析 View */
CREATE OR REPLACE VIEW v_order_items_agg AS
SELECT
    order_id,
    COUNT(*) AS item_count,
    COUNT(DISTINCT product_id) AS product_count,
    COUNT(DISTINCT seller_id) AS seller_count,
    SUM(price) AS item_gmv,
    SUM(freight_value) AS freight_total
FROM order_items
GROUP BY order_id;

SELECT *
FROM v_order_items_agg
ORDER BY item_count DESC
LIMIT 20;

SELECT
    COUNT(*) AS order_count,
    SUM(item_gmv) AS total_item_gmv,
    SUM(freight_total) AS total_freight
FROM v_order_items_agg;

SELECT
    SUM(price),
    SUM(freight_value)
FROM order_items;

CREATE OR REPLACE VIEW v_payments_agg AS
SELECT
    order_id,
    COUNT(*) AS payment_record_count,
    COUNT(DISTINCT payment_type) AS payment_type_count,
    GROUP_CONCAT(
        DISTINCT payment_type
        ORDER BY payment_type
        SEPARATOR ', '
    ) AS payment_methods,
    MAX(payment_installments) AS max_installments,
    SUM(payment_value) AS payment_total
FROM payments
GROUP BY order_id;

SELECT *
FROM v_payments_agg
WHERE payment_record_count > 1
ORDER BY payment_record_count DESC
LIMIT 20;

SELECT
    COUNT(*) AS order_count,
    SUM(payment_total) AS total_payment
FROM v_payments_agg;

CREATE OR REPLACE VIEW v_latest_review AS review_ranked
SELECT
    review_id,
    order_id,
    review_score,
    review_comment_title,
    review_comment_message,
    review_creation_date,
    review_answer_timestamp
FROM (
    SELECT
        r.*,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY
                review_answer_timestamp DESC,
                review_creation_date DESC,
                review_id DESC
        ) AS rn
    FROM reviews r
)
WHERE rn = 1;

SELECT
    COUNT(*) AS rows_count,
    COUNT(DISTINCT order_id) AS distinct_orders
FROM v_latest_review;

CREATE OR REPLACE VIEW v_order_analysis AS
SELECT
    o.order_id,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    YEAR(o.order_purchase_timestamp)  AS purchase_year,
    MONTH(o.order_purchase_timestamp) AS purchase_month,
    DATE_FORMAT(
            o.order_purchase_timestamp,
            '%Y-%m'
    )                                 AS purchase_year_month,
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,
    oi.item_count,
    oi.product_count,
    oi.seller_count,
    oi.item_gmv,
    oi.freight_total,
    oi.item_gmv + oi.freight_total AS item_value_with_freight,
    p.payment_record_count,
    p.payment_type_count,
    p.payment_methods,
    p.max_installments,
    p.payment_total,
    r.review_score,
    ROUND(
            TIMESTAMPDIFF(
                    HOUR,
                    o.order_purchase_timestamp,
                    o.order_delivered_customer_date
            ) / 24.0,
            2
    ) AS delivery_days,
    ROUND(
            TIMESTAMPDIFF(
                    HOUR,
                    o.order_estimated_delivery_date,
                    o.order_delivered_customer_date
            ) / 24.0,
            2
    ) AS delay_days,
    CASE

        WHEN o.order_delivered_customer_date IS NULL
            THEN NULL

        WHEN o.order_delivered_customer_date >
             o.order_estimated_delivery_date
            THEN 1

        ELSE 0
        END AS is_late
FROM orders o
         LEFT JOIN customers c
                   ON o.customer_id = c.customer_id
         LEFT JOIN v_order_items_agg oi
                   ON o.order_id = oi.order_id
         LEFT JOIN v_payments_agg p
                   ON o.order_id = p.order_id
         LEFT JOIN v_latest_review r
                   ON o.order_id = r.order_id;

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT order_id) AS distinct_orders
FROM v_order_analysis;

SELECT
    SUM(item_gmv) AS view_gmv
FROM v_order_analysis;

SELECT SUM(price)
FROM order_items;

SELECT *
FROM v_order_analysis
LIMIT 20;

SELECT
    order_status,
    COUNT(*) AS order_count,
    ROUND(
        COUNT(*) * 100.0 /
        SUM(COUNT(*)) OVER (),
        2
    ) AS order_pct
FROM v_order_analysis
GROUP BY order_status
ORDER BY order_count DESC;

CREATE OR REPLACE VIEW v_completed_orders AS
SELECT *
FROM v_order_analysis
WHERE order_status = 'delivered';

/* 4. 平台整体经营表现 */
SELECT
    COUNT(DISTINCT order_id) AS orders,
    COUNT(DISTINCT customer_unique_id) AS customers,
    ROUND(
            SUM(item_gmv),
            2
    ) AS gmv,
    ROUND(
        SUM(item_gmv) /
        COUNT(DISTINCT order_id),
        2
    ) AS aov,
    SUM(item_count) AS items_sold
FROM v_completed_orders
WHERE order_purchase_timestamp >= '2017-01-01'
  AND order_purchase_timestamp < '2018-09-01';

SELECT
    DATE_FORMAT(
        order_purchase_timestamp,
        '%Y-%m'
    ) AS purchase_month,
    COUNT(DISTINCT order_id) AS orders,
    COUNT(DISTINCT customer_unique_id) AS customers,
    ROUND(SUM(item_gmv), 2) AS gmv,
    ROUND(
        SUM(item_gmv) /
        COUNT(DISTINCT order_id),
        2
    ) AS aov
FROM v_completed_orders
WHERE order_purchase_timestamp >= '2017-01-01'
  AND order_purchase_timestamp < '2018-09-01'
GROUP BY
    DATE_FORMAT(
        order_purchase_timestamp,
        '%Y-%m'
    )
ORDER BY purchase_month;

WITH monthly_kpi AS (
    SELECT
        DATE_FORMAT(
            order_purchase_timestamp,
            '%Y-%m'
        ) AS purchase_month,
        COUNT(DISTINCT order_id) AS orders,
        COUNT(DISTINCT customer_unique_id) AS customers,
        SUM(item_gmv) AS gmv,
        SUM(item_gmv) /
        COUNT(DISTINCT order_id) AS aov
    FROM v_completed_orders
    WHERE order_purchase_timestamp >= '2017-01-01'
      AND order_purchase_timestamp < '2018-09-01'
    GROUP BY
        DATE_FORMAT(
            order_purchase_timestamp,
            '%Y-%m'
        )
),
monthly_growth AS (
    SELECT
        *,
        LAG(orders) OVER (
            ORDER BY purchase_month
        ) AS previous_orders,

        LAG(gmv) OVER (
            ORDER BY purchase_month
        ) AS previous_gmv
    FROM monthly_kpi
)
SELECT
    purchase_month,
    orders,
    ROUND(gmv, 2) AS gmv,
    ROUND(aov, 2) AS aov,
    ROUND(
        (orders - previous_orders)
        / previous_orders * 100,
        2
    ) AS orders_mom_pct,
    ROUND(
        (gmv - previous_gmv)
        / previous_gmv * 100,
        2
    ) AS gmv_mom_pct
FROM monthly_growth
ORDER BY purchase_month;

SELECT
    YEAR(order_purchase_timestamp) AS year,
    COUNT(DISTINCT order_id) AS orders,
    COUNT(DISTINCT customer_unique_id) AS customers,
    ROUND(SUM(item_gmv), 2) AS gmv,
    ROUND(
        SUM(item_gmv) /
        COUNT(DISTINCT order_id),
        2
    ) AS aov
FROM v_completed_orders
WHERE YEAR(order_purchase_timestamp)
      IN (2017, 2018)
  AND MONTH(order_purchase_timestamp)
      BETWEEN 1 AND 8
GROUP BY
    YEAR(order_purchase_timestamp)
ORDER BY year;

/* 5. State 地域经营 + 配送问题 */
WITH state_kpi AS (
    SELECT
        customer_state,
        COUNT(DISTINCT order_id) AS orders,
        COUNT(DISTINCT customer_unique_id) AS customers,
        SUM(item_gmv) AS gmv
    FROM v_completed_orders
    WHERE order_purchase_timestamp >= '2017-01-01'
      AND order_purchase_timestamp < '2018-09-01'

    GROUP BY customer_state
)
SELECT
    customer_state,
    orders,
    customers,
    ROUND(gmv, 2) AS gmv,
    ROUND(
        gmv / orders,
        2
    ) AS aov,
    ROUND(
        gmv / SUM(gmv) OVER () * 100,
        2
    ) AS gmv_share_pct
FROM state_kpi
ORDER BY gmv DESC;

/* 6. Category 品类经营 + 配送表现 */
WITH category_detail AS (
    SELECT
        v.order_id,
        v.customer_unique_id,
        oi.order_item_id,
        oi.price,
        oi.freight_value,
        COALESCE(
            ct.product_category_name_english,
            p.product_category_name,
            'unknown'
        ) AS product_category
    FROM v_completed_orders v
    JOIN order_items oi
        ON v.order_id = oi.order_id
    LEFT JOIN products p
        ON oi.product_id = p.product_id
    LEFT JOIN category_translation ct
        ON p.product_category_name
        = ct.product_category_name
    WHERE v.order_purchase_timestamp >= '2017-01-01'
      AND v.order_purchase_timestamp < '2018-09-01'
),
category_kpi AS (
    SELECT
        product_category,
        COUNT(DISTINCT order_id) AS orders,
        COUNT(DISTINCT customer_unique_id) AS customers,
        COUNT(*) AS items_sold,
        SUM(price) AS gmv,
        AVG(price) AS avg_item_price
    FROM category_detail
    GROUP BY product_category
)
SELECT
    product_category,
    orders,
    customers,
    items_sold,
    ROUND(gmv, 2) AS gmv,
    ROUND(avg_item_price, 2) AS avg_item_price,
    ROUND(
        gmv / SUM(gmv) OVER () * 100,
        2
    ) AS gmv_share_pct
FROM category_kpi
ORDER BY gmv DESC;

WITH order_category AS (
    SELECT
        v.order_id,
        COALESCE(
            ct.product_category_name_english,
            p.product_category_name,
            'unknown'
        ) AS product_category,
        SUM(oi.price) AS category_gmv,
        MAX(v.review_score) AS review_score,
        MAX(v.is_late) AS is_late,
        MAX(v.delivery_days) AS delivery_days
    FROM v_completed_orders v
    JOIN order_items oi
        ON v.order_id = oi.order_id
    LEFT JOIN products p
        ON oi.product_id = p.product_id
    LEFT JOIN category_translation ct
        ON p.product_category_name
        = ct.product_category_name
    WHERE v.order_purchase_timestamp >= '2017-01-01'
      AND v.order_purchase_timestamp < '2018-09-01'
    GROUP BY
        v.order_id,
        COALESCE(
            ct.product_category_name_english,
            p.product_category_name,
            'unknown'
        )
),
category_quality AS (
    SELECT
        product_category,
        COUNT(*) AS orders,
        SUM(category_gmv) AS gmv,
        AVG(review_score) AS avg_review,
        AVG(is_late) * 100 AS late_rate_pct,
        AVG(delivery_days) AS avg_delivery_days
    FROM order_category
    GROUP BY product_category
)
SELECT
    product_category,
    orders,
    ROUND(gmv, 2) AS gmv,
    ROUND(avg_review, 2) AS avg_review,
    ROUND(late_rate_pct, 2) AS late_rate_pct,
    ROUND(avg_delivery_days, 2)
        AS avg_delivery_days
FROM category_quality
WHERE orders >= 1000
ORDER BY avg_review ASC;

/* 7. 配送体验与客户评分 */
SELECT
    ROUND(AVG(review_score), 2)
        AS avg_review,
    ROUND(AVG(is_late) * 100, 2)
        AS late_rate_pct,
    ROUND(AVG(delivery_days), 2)
        AS avg_delivery_days
FROM v_completed_orders
WHERE order_purchase_timestamp >= '2017-01-01'
  AND order_purchase_timestamp < '2018-09-01';

SELECT
    CASE
        WHEN is_late = 1
            THEN 'Late'
        WHEN is_late = 0
            THEN 'On Time'
        ELSE 'Unknown'
    END AS delivery_status,
    COUNT(DISTINCT order_id) AS orders,
    ROUND(
        AVG(review_score),
        2
    ) AS avg_review,
    ROUND(
        AVG(delivery_days),
        2
    ) AS avg_delivery_days
FROM v_completed_orders
WHERE order_purchase_timestamp >= '2017-01-01'
  AND order_purchase_timestamp < '2018-09-01'
  AND is_late IS NOT NULL
GROUP BY is_late
ORDER BY is_late;

WITH state_delay AS (
    SELECT
        customer_state,
        COUNT(DISTINCT order_id) AS orders,
        SUM(
            CASE
                WHEN is_late = 1 THEN 1
                ELSE 0
            END
        ) AS late_orders,
        AVG(is_late) * 100 AS late_rate_pct,
        AVG(review_score) AS avg_review,
        AVG(delivery_days) AS avg_delivery_days
    FROM v_completed_orders
    WHERE order_purchase_timestamp >= '2017-01-01'
      AND order_purchase_timestamp < '2018-09-01'
      AND is_late IS NOT NULL
    GROUP BY customer_state
),
state_total AS (
    SELECT
        *,
        SUM(late_orders) OVER () AS total_late_orders
    FROM state_delay
),
state_pareto AS (
    SELECT
        *,
        late_orders /
        total_late_orders * 100
            AS late_share_pct,
        SUM(late_orders) OVER (
            ORDER BY late_orders DESC,
                     customer_state
        ) /
        total_late_orders * 100
            AS cumulative_late_share_pct,
        RANK() OVER (
            ORDER BY late_orders DESC
        ) AS late_order_rank
    FROM state_total
)
SELECT
    customer_state,
    orders,
    late_orders,
    ROUND(late_rate_pct, 2)
        AS late_rate_pct,
    ROUND(late_share_pct, 2)
        AS late_share_pct,
    ROUND(cumulative_late_share_pct, 2)
        AS cumulative_late_share_pct,
    ROUND(avg_review, 2)
        AS avg_review,
    ROUND(avg_delivery_days, 2)
        AS avg_delivery_days,
    late_order_rank
FROM state_pareto
ORDER BY late_orders DESC;

WITH order_category AS (
    SELECT
        v.order_id,
        COALESCE(
            ct.product_category_name_english,
            p.product_category_name,
            'unknown'
        ) AS product_category,
        SUM(oi.price) AS category_gmv,
        MAX(v.is_late) AS is_late,
        MAX(v.review_score) AS review_score,
        MAX(v.delivery_days) AS delivery_days
    FROM v_completed_orders v
    JOIN order_items oi
        ON v.order_id = oi.order_id
    LEFT JOIN products p
        ON oi.product_id = p.product_id
    LEFT JOIN category_translation ct
        ON p.product_category_name
           = ct.product_category_name
    WHERE v.order_purchase_timestamp >= '2017-01-01'
      AND v.order_purchase_timestamp < '2018-09-01'
      AND v.is_late IS NOT NULL
    GROUP BY
        v.order_id,
        COALESCE(
            ct.product_category_name_english,
            p.product_category_name,
            'unknown'
        )
),
category_delay AS (
    SELECT
        product_category,
        COUNT(*) AS orders,
        SUM(is_late) AS late_orders,
        AVG(is_late) * 100 AS late_rate_pct,
        SUM(category_gmv) AS gmv,
        AVG(review_score) AS avg_review,
        AVG(delivery_days) AS avg_delivery_days
    FROM order_category
    GROUP BY product_category
)
SELECT
    product_category,
    orders,
    late_orders,
    ROUND(late_rate_pct, 2)
        AS late_rate_pct,
    ROUND(gmv, 2)
        AS gmv,
    ROUND(avg_review, 2)
        AS avg_review,
    ROUND(avg_delivery_days, 2)
        AS avg_delivery_days
FROM category_delay
ORDER BY late_orders DESC;

/* 8. Seller 配送问题 */
WITH order_seller AS (
    SELECT
        v.order_id,
        oi.seller_id,
        SUM(oi.price) AS seller_gmv,
        MAX(v.is_late) AS is_late,
        MAX(v.review_score) AS review_score,
        MAX(v.delivery_days) AS delivery_days
    FROM v_completed_orders v
    JOIN order_items oi
        ON v.order_id = oi.order_id
    WHERE v.order_purchase_timestamp >= '2017-01-01'
      AND v.order_purchase_timestamp < '2018-09-01'
      AND v.is_late IS NOT NULL
    GROUP BY
        v.order_id,
        oi.seller_id
),
seller_kpi AS (
    SELECT
        seller_id,
        COUNT(*) AS orders,
        SUM(is_late) AS late_orders,
        AVG(is_late) * 100
            AS late_rate_pct,
        SUM(seller_gmv) AS gmv,
        AVG(review_score)
            AS avg_review,
        AVG(delivery_days)
            AS avg_delivery_days
    FROM order_seller
    GROUP BY seller_id
),
seller_filtered AS (
    SELECT *
    FROM seller_kpi
    WHERE orders >= 100
)
SELECT
    LEFT(seller_id, 8) AS seller,
    orders,
    late_orders,
    ROUND(late_rate_pct, 2)
        AS late_rate_pct,
    ROUND(gmv, 2)
        AS gmv,
    ROUND(avg_review, 2)
        AS avg_review,
    ROUND(avg_delivery_days, 2)
        AS avg_delivery_days,
    RANK() OVER (
        ORDER BY late_orders DESC
    ) AS late_volume_rank,
    RANK() OVER (
        ORDER BY late_rate_pct DESC
    ) AS late_rate_rank
FROM seller_filtered
ORDER BY late_orders DESC
LIMIT 20;

WITH customer_orders AS (
    SELECT
        customer_unique_id,
        COUNT(*) AS orders,
        SUM(item_gmv) AS total_gmv,
        AVG(item_gmv) AS avg_order_value,
        MIN(order_purchase_timestamp)
            AS first_purchase,
        MAX(order_purchase_timestamp)
            AS last_purchase
    FROM v_completed_orders
    WHERE order_purchase_timestamp >= '2017-01-01'
      AND order_purchase_timestamp < '2018-09-01'
      AND customer_unique_id IS NOT NULL
    GROUP BY customer_unique_id
)
SELECT
    orders AS purchase_frequency,
    COUNT(*) AS customers,
    ROUND(
        COUNT(*) * 100.0 /
        SUM(COUNT(*)) OVER (),
        2
    ) AS customer_share_pct
FROM customer_orders
GROUP BY orders
ORDER BY orders;

/* 9. Customer Analysis：复购率和购买频次 */
WITH customer_orders AS (
    SELECT
        customer_unique_id,
        COUNT(*) AS orders
    FROM v_completed_orders
    WHERE order_purchase_timestamp >= '2017-01-01'
      AND order_purchase_timestamp < '2018-09-01'
      AND customer_unique_id IS NOT NULL
    GROUP BY customer_unique_id
)
SELECT
    COUNT(*) AS customers,
      SUM(
        CASE
            WHEN orders >= 2 THEN 1
            ELSE 0
        END
    ) AS repeat_customers,
    ROUND(
        SUM(
            CASE
                WHEN orders >= 2 THEN 1
                ELSE 0
            END
        ) * 100.0 / COUNT(*),
        2
    ) AS repeat_purchase_rate_pct
FROM customer_orders;

WITH customer_orders AS (
    SELECT
        customer_unique_id,
        COUNT(*) AS orders,
        SUM(item_gmv) AS total_gmv
    FROM v_completed_orders
    WHERE order_purchase_timestamp >= '2017-01-01'
      AND order_purchase_timestamp < '2018-09-01'
      AND customer_unique_id IS NOT NULL
    GROUP BY customer_unique_id
),
customer_segment AS (
    SELECT
        customer_unique_id,
        orders,
        total_gmv,
        CASE
            WHEN orders = 1
                THEN 'One-time'
            WHEN orders = 2
                THEN 'Repeat'
            ELSE 'High-frequency'
        END AS customer_type
    FROM customer_orders
)
SELECT
    customer_type,
    COUNT(*) AS customers,
    SUM(orders) AS orders,
    ROUND(SUM(total_gmv), 2) AS gmv,
    ROUND(AVG(total_gmv), 2)
        AS avg_customer_gmv,
    ROUND(
        COUNT(*) * 100.0 /
        SUM(COUNT(*)) OVER (),
        2
    ) AS customer_share_pct
FROM customer_segment
GROUP BY customer_type
ORDER BY customers DESC;

WITH ranked_orders AS (
    SELECT
        order_id,
        customer_unique_id,
        order_purchase_timestamp,
        item_gmv,
        ROW_NUMBER() OVER (
            PARTITION BY customer_unique_id
            ORDER BY
                order_purchase_timestamp,
                order_id
        ) AS order_number
    FROM v_completed_orders
    WHERE customer_unique_id IS NOT NULL
)
SELECT *
FROM ranked_orders
WHERE customer_unique_id IS NOT NULL
ORDER BY
    customer_unique_id,
    order_number
LIMIT 100;

WITH ranked_orders AS (
    SELECT
        order_id,
        customer_unique_id,
        order_purchase_timestamp,
        item_gmv,
        ROW_NUMBER() OVER (
            PARTITION BY customer_unique_id
            ORDER BY
                order_purchase_timestamp,
                order_id
        ) AS order_number
    FROM v_completed_orders
    WHERE customer_unique_id IS NOT NULL
),
monthly_customer_type AS (
    SELECT
        DATE_FORMAT(
            order_purchase_timestamp,
            '%Y-%m'
        ) AS month,
        CASE
            WHEN order_number = 1
                THEN 'New'
            ELSE 'Returning'
        END AS customer_type,
        COUNT(*) AS orders,
        SUM(item_gmv) AS gmv
    FROM ranked_orders
    WHERE order_purchase_timestamp >= '2017-01-01'
      AND order_purchase_timestamp < '2018-09-01'
    GROUP BY
        DATE_FORMAT(
            order_purchase_timestamp,
            '%Y-%m'
        ),
        CASE
            WHEN order_number = 1
                THEN 'New'
            ELSE 'Returning'
        END
)
SELECT
    month,
    customer_type,
    orders,
    ROUND(gmv, 2) AS gmv
FROM monthly_customer_type
ORDER BY
    month,
    customer_type;

WITH ranked_orders AS (
    SELECT
        order_id,
        customer_unique_id,
        order_purchase_timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY customer_unique_id
            ORDER BY
                order_purchase_timestamp,
                order_id
        ) AS order_number
    FROM v_completed_orders
    WHERE customer_unique_id IS NOT NULL
)
SELECT
    DATE_FORMAT(
        order_purchase_timestamp,
        '%Y-%m'
    ) AS month,
    COUNT(*) AS orders,
    SUM(
        CASE
            WHEN order_number >= 2 THEN 1
            ELSE 0
        END
    ) AS repeat_orders,
    ROUND(
        SUM(
            CASE
                WHEN order_number >= 2 THEN 1
                ELSE 0
            END
        ) * 100.0 /
        COUNT(*),
        2
    ) AS repeat_order_share_pct
FROM ranked_orders
WHERE order_purchase_timestamp >= '2017-01-01'
  AND order_purchase_timestamp < '2018-09-01'
GROUP BY
    DATE_FORMAT(
        order_purchase_timestamp,
        '%Y-%m'
    )
ORDER BY month;

WITH customer_month AS (
    SELECT DISTINCT
        customer_unique_id,
        DATE_FORMAT(
            order_purchase_timestamp,
            '%Y-%m-01'
        ) AS order_month
    FROM v_completed_orders
    WHERE order_purchase_timestamp >= '2017-01-01'
      AND order_purchase_timestamp < '2018-09-01'
      AND customer_unique_id IS NOT NULL
),
customer_cohort AS (
    SELECT
        customer_unique_id,
        MIN(order_month)
            AS cohort_month
    FROM customer_month
    GROUP BY customer_unique_id
),
cohort_activity AS (
    SELECT
        cm.customer_unique_id,
        cc.cohort_month,
        cm.order_month,
        TIMESTAMPDIFF(
            MONTH,
            cc.cohort_month,
            cm.order_month
        ) AS month_number
    FROM customer_month cm
    JOIN customer_cohort cc
        ON cm.customer_unique_id
           = cc.customer_unique_id
),
cohort_counts AS (
    SELECT
        cohort_month,
        month_number,
        COUNT(DISTINCT customer_unique_id)
            AS active_customers
    FROM cohort_activity
    GROUP BY
        cohort_month,
        month_number
),
cohort_size AS (
    SELECT
        cohort_month,
        active_customers AS cohort_customers
    FROM cohort_counts
    WHERE month_number = 0
)
SELECT
    c.cohort_month,
    c.month_number,
    c.active_customers,
    s.cohort_customers,
    ROUND(
        c.active_customers * 100.0 /
        s.cohort_customers,
        2
    ) AS retention_rate_pct
FROM cohort_counts c
JOIN cohort_size s
    ON c.cohort_month = s.cohort_month
ORDER BY
    c.cohort_month,
    c.month_number;

/* 10. New vs Returning 总体价值比较 */
WITH ranked_orders AS (
    SELECT
        order_id,
        customer_unique_id,
        order_purchase_timestamp,
        item_gmv,
        ROW_NUMBER() OVER (
            PARTITION BY customer_unique_id
            ORDER BY
                order_purchase_timestamp,
                order_id
        ) AS order_number
    FROM v_completed_orders
    WHERE customer_unique_id IS NOT NULL
),
customer_type AS (
    SELECT
        *,
        CASE
            WHEN order_number = 1
                THEN 'New'
            ELSE 'Returning'
        END AS customer_type
    FROM ranked_orders
    WHERE order_purchase_timestamp >= '2017-01-01'
      AND order_purchase_timestamp < '2018-09-01'
),
summary AS (
    SELECT
        customer_type,
        COUNT(*) AS orders,
        COUNT(DISTINCT customer_unique_id)
            AS customers,
        SUM(item_gmv) AS gmv,
        AVG(item_gmv) AS aov
    FROM customer_type
    GROUP BY customer_type
)
SELECT
    customer_type,
    orders,
    customers,
    ROUND(gmv, 2) AS gmv,
    ROUND(aov, 2) AS aov,
    ROUND(
        gmv * 100.0 /
        SUM(gmv) OVER (),
        2
    ) AS gmv_share_pct
FROM summary
ORDER BY gmv DESC;

WITH ordered_purchases AS (
    SELECT
        customer_unique_id,
        order_id,
        order_purchase_timestamp,
        LAG(order_purchase_timestamp) OVER (
            PARTITION BY customer_unique_id
            ORDER BY
                order_purchase_timestamp,
                order_id
        ) AS previous_purchase_date
    FROM v_completed_orders
    WHERE customer_unique_id IS NOT NULL
),
purchase_gap AS (
    SELECT
        customer_unique_id,
        order_id,
        order_purchase_timestamp,
        previous_purchase_date,
        DATEDIFF(
            order_purchase_timestamp,
            previous_purchase_date
        ) AS purchase_gap_days
    FROM ordered_purchases
    WHERE previous_purchase_date IS NOT NULL
      AND order_purchase_timestamp >= '2017-01-01'
      AND order_purchase_timestamp < '2018-09-01'
)
SELECT
    COUNT(*) AS repeat_orders,
    ROUND(
        AVG(purchase_gap_days),
        2
    ) AS avg_purchase_gap_days,
    MIN(purchase_gap_days)
        AS min_purchase_gap_days,
    MAX(purchase_gap_days)
        AS max_purchase_gap_days
FROM purchase_gap;

WITH ordered_purchases AS (
    SELECT
        customer_unique_id,
        order_id,
        order_purchase_timestamp,
        LAG(order_purchase_timestamp) OVER (
            PARTITION BY customer_unique_id
            ORDER BY
                order_purchase_timestamp,
                order_id
        ) AS previous_purchase_date
    FROM v_completed_orders
    WHERE customer_unique_id IS NOT NULL
),
purchase_gap AS (
    SELECT
        customer_unique_id,
        DATEDIFF(
            order_purchase_timestamp,
            previous_purchase_date
        ) AS purchase_gap_days
    FROM ordered_purchases
    WHERE previous_purchase_date IS NOT NULL
      AND order_purchase_timestamp >= '2017-01-01'
      AND order_purchase_timestamp < '2018-09-01'
),
gap_bucket AS (
    SELECT
        CASE
            WHEN purchase_gap_days <= 30
                THEN '01. 0-30 days'
            WHEN purchase_gap_days <= 60
                THEN '02. 31-60 days'
            WHEN purchase_gap_days <= 90
                THEN '03. 61-90 days'
            WHEN purchase_gap_days <= 180
                THEN '04. 91-180 days'
            ELSE '05. 180+ days'
        END AS gap_group
    FROM purchase_gap
    WHERE purchase_gap_days >= 0
)
SELECT
    gap_group,
    COUNT(*) AS repeat_orders,
    ROUND(
        COUNT(*) * 100.0 /
        SUM(COUNT(*)) OVER (),
        2
    ) AS share_pct
FROM gap_bucket
GROUP BY gap_group
ORDER BY gap_group;

WITH ranked_orders AS (
    SELECT
        customer_unique_id,
        order_id,
        order_purchase_timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY customer_unique_id
            ORDER BY
                order_purchase_timestamp,
                order_id
        ) AS order_number
    FROM v_completed_orders
    WHERE customer_unique_id IS NOT NULL
),
first_second AS (
    SELECT
        customer_unique_id,
        MIN(
            CASE
                WHEN order_number = 1
                THEN order_purchase_timestamp
            END
        ) AS first_purchase,
        MIN(
            CASE
                WHEN order_number = 2
                THEN order_purchase_timestamp
            END
        ) AS second_purchase
    FROM ranked_orders
    GROUP BY customer_unique_id
)
SELECT
    COUNT(second_purchase)
        AS customers_with_second_purchase,
    ROUND(
        AVG(
            DATEDIFF(
                second_purchase,
                first_purchase
            )
        ),
        2
    ) AS avg_days_to_second_purchase
FROM first_second
WHERE first_purchase >= '2017-01-01'
  AND first_purchase < '2018-09-01';

/* 11 Top 10% 高价值客户 GMV 贡献 */
WITH customer_value AS (
    SELECT
        customer_unique_id,
        COUNT(*) AS orders,
        SUM(item_gmv) AS total_gmv
    FROM v_completed_orders
    WHERE order_purchase_timestamp >= '2017-01-01'
      AND order_purchase_timestamp < '2018-09-01'
      AND customer_unique_id IS NOT NULL
    GROUP BY customer_unique_id
),
ranked_customers AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            ORDER BY
                total_gmv DESC,
                customer_unique_id
        ) AS customer_rank,
        COUNT(*) OVER ()
            AS total_customers,
        SUM(total_gmv) OVER ()
            AS platform_gmv
    FROM customer_value
)
SELECT
    COUNT(*) AS top_10_pct_customers,
    ROUND(
        SUM(total_gmv),
        2
    ) AS top_10_pct_gmv,
    ROUND(
        SUM(total_gmv) * 100.0 /
        MAX(platform_gmv),
        2
    ) AS top_10_pct_gmv_share
FROM ranked_customers
WHERE customer_rank
      <= CEIL(total_customers * 0.10);

/* 13. Month 1 / 2 / 3 平均购买留存 */
WITH customer_month AS (
    SELECT DISTINCT
        customer_unique_id,
        CAST(
            DATE_FORMAT(
                order_purchase_timestamp,
                '%Y-%m-01'
            ) AS DATE
        ) AS order_month
    FROM v_completed_orders
    WHERE customer_unique_id IS NOT NULL
),
customer_cohort AS (
    SELECT
        customer_unique_id,
        MIN(order_month) AS cohort_month
    FROM customer_month
    GROUP BY customer_unique_id
),
cohort_activity AS (
    SELECT
        cm.customer_unique_id,
        cc.cohort_month,
        cm.order_month,
        TIMESTAMPDIFF(
            MONTH,
            cc.cohort_month,
            cm.order_month
        ) AS month_number
    FROM customer_month cm
    JOIN customer_cohort cc
        ON cm.customer_unique_id
         = cc.customer_unique_id
),
cohort_counts AS (
    SELECT
        cohort_month,
        month_number,
        COUNT(DISTINCT customer_unique_id)
            AS customers
    FROM cohort_activity
    GROUP BY
        cohort_month,
        month_number
),
cohort_size AS (
    SELECT
        cohort_month,
        customers AS cohort_customers
    FROM cohort_counts
    WHERE month_number = 0
),
retention AS (
    SELECT
        c.cohort_month,
        c.month_number,
        c.customers * 100.0 /
        s.cohort_customers
            AS retention_rate
    FROM cohort_counts c
    JOIN cohort_size s
        ON c.cohort_month = s.cohort_month
)
SELECT
    month_number,
    ROUND(
        AVG(retention_rate),
        2
    ) AS avg_retention_rate_pct
FROM retention
WHERE cohort_month >= '2017-01-01'
  AND cohort_month <= '2018-05-01'
  AND month_number IN (1, 2, 3)
GROUP BY month_number
ORDER BY month_number;