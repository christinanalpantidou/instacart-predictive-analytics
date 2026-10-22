-- For each pair user-product, computes the average cart position of the specific product
SELECT o.user_id,
	   opp.product_id,
	   AVG(opp.add_to_cart_order) AS user_product_avg_cart_position
FROM orders o
INNER JOIN order_products_prior opp USING(order_id)
GROUP BY o.user_id, opp.product_id;

-- For each pair user-product, calculates the average user's order gap restricted to orders 
-- that included the given product
SELECT o.user_id,
	   opp.product_id,
	   AVG(o.days_since_prior_order) AS user_order_tempo
FROM orders o
INNER JOIN order_products_prior opp USING(order_id)
GROUP BY o.user_id, opp.product_id;

-- For each pair user-product, calculates the number of days that have elapsed from 
-- the first order to the last order that included the given product and the average days 
-- between consecutive purchases of that specific product (true repurchase cadence). 
-- NULL when bought only once.
WITH 

order_cumulative_days AS (
SELECT user_id, 
       order_number,
       SUM(COALESCE(days_since_prior_order, 0)) OVER (PARTITION BY user_id ORDER BY order_number) AS cumulative_days
FROM orders
WHERE eval_set = 'prior'
),

user_product_first_last AS (
SELECT o.user_id, 
       opp.product_id,
	   COUNT(DISTINCT o.order_id) AS user_product_order_count,
       MIN(o.order_number) AS first_order_number,
       MAX(o.order_number) AS last_order_number
FROM orders o
INNER JOIN order_products_prior opp USING(order_id)
GROUP BY o.user_id, opp.product_id
)

SELECT upl.user_id,
       upl.product_id,
       (ocd_last.cumulative_days - ocd_first.cumulative_days) AS user_product_days_from_first_to_last,
	   (ocd_last.cumulative_days - ocd_first.cumulative_days)::NUMERIC
           / NULLIF(upl.user_product_order_count - 1, 0) AS user_product_avg_repurchase_interval
FROM user_product_first_last upl
INNER JOIN order_cumulative_days ocd_first
    ON upl.user_id = ocd_first.user_id AND upl.first_order_number = ocd_first.order_number
INNER JOIN order_cumulative_days ocd_last
    ON upl.user_id = ocd_last.user_id AND upl.last_order_number = ocd_last.order_number;

-- For each user–product combination, counts how many times the user ordered that product, 
-- and calculates that count as a share of all products ordered by that user
SELECT 
	o.user_id, 
	opp.product_id, 
	COUNT(*) AS user_product_order_count,
	COUNT(*)/ SUM(COUNT(*)) OVER(PARTITION BY o.user_id) AS user_product_order_share
FROM orders o
INNER JOIN order_products_prior opp USING(order_id)
GROUP BY o.user_id, opp.product_id;

-- 1.For each user–product pair, calculates the proportion of the user's entire order history
-- included that specific product
-- 2.For each user-product pair, divides the user's total orders included the given product 
-- divided by orders since first purchase.In essence, it answers 
-- "given that the user has known about this product, how consistently do they buy it"
WITH 

user_product_orders AS (
SELECT o.user_id, 
       opp.product_id,
       COUNT(DISTINCT o.order_id) AS user_product_order_count
FROM orders o 
INNER JOIN order_products_prior opp USING(order_id)
GROUP BY o.user_id, opp.product_id
),

user_product_first AS (
SELECT o.user_id, 
	   opp.product_id, 
	   MIN(o.order_number) AS first_order_number
FROM orders o
INNER JOIN order_products_prior opp USING(order_id)
GROUP BY o.user_id, opp.product_id
),

user_totals AS (
SELECT user_id, 
       COUNT(order_id) AS user_total_order_count,
       MAX(order_number) AS user_max_order_number
FROM orders
WHERE eval_set = 'prior'
GROUP BY user_id
)

SELECT upo.user_id,
       upo.product_id,
       upo.user_product_order_count,
       upo.user_product_order_count::NUMERIC 
           / ut.user_total_order_count AS user_product_order_rate_overall,
	   (ut.user_max_order_number - upf.first_order_number + 1) AS product_orders_since_first_purchase,
       upo.user_product_order_count::NUMERIC 
           / (ut.user_max_order_number - upf.first_order_number + 1) AS user_product_order_rate_since_first
FROM user_product_orders upo
INNER JOIN user_product_first upf USING(user_id, product_id)
INNER JOIN user_totals ut USING(user_id);

-- For each user–product pair, calculates what share of all orders containing that 
-- product belong to that specific user
SELECT o.user_id, 
		opp.product_id, 
		COUNT(DISTINCT o.order_id) / 
		SUM(COUNT(o.order_id)) OVER(PARTITION BY opp.product_id) AS user_share_of_product_orders
FROM orders o
INNER JOIN order_products_prior opp USING(order_id)
GROUP BY o.user_id, opp.product_id;

-- For each user–product pair where the product appeared in the user's first order, 
-- counts how many times the user reordered it in subsequent orders
WITH 

first_order AS (
SELECT DISTINCT o.user_id, opp.product_id
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
WHERE o.order_number = 1
)

SELECT 
    opp.product_id,
	o.user_id,
    COUNT(*) AS user_product_reorder_after_first_count
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
INNER JOIN first_order fo 
    ON o.user_id = fo.user_id 
    AND opp.product_id = fo.product_id
WHERE opp.reordered = true
GROUP BY o.user_id, opp.product_id;

-- For each user–product pair, calculates the proportion of that product's orders 
-- by that user which were reorders rather than first-time purchases
WITH

reorders AS (
SELECT opp.product_id,
		o.user_id,
		COUNT(o.order_id) AS user_product_reorder_count
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
WHERE opp.reordered = true
GROUP BY opp.product_id, o.user_id
),

total AS (
SELECT opp.product_id,
		o.user_id,
		COUNT(o.order_id) AS user_product_order_count
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
GROUP BY opp.product_id, o.user_id
ORDER BY o.user_id
)

SELECT t.product_id,
		t.user_id,
		r.user_product_reorder_count,
		COALESCE(r.user_product_reorder_count, 0):: NUMERIC / user_product_order_count AS user_product_reorder_rate
FROM total t
LEFT JOIN reorders r 
ON t.product_id = r.product_id AND t.user_id = r.user_id;

-- For each user-product pair, flags whether the product appeared in the user's first order
-- AND in his last order, returning 1 if both conditions are met, else 0 is returned 
WITH 

first_order AS (
SELECT DISTINCT opp.product_id, o.user_id
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
WHERE o.order_number = 1
),

last_order AS (
SELECT DISTINCT opp.product_id, o.user_id
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
WHERE (o.user_id, o.order_number) IN (
        SELECT user_id, MAX(order_number)
        FROM orders
        WHERE eval_set = 'prior'
        GROUP BY user_id
    	)
),

both_orders AS (
SELECT product_id, user_id FROM first_order
INTERSECT
SELECT product_id, user_id FROM last_order
)

SELECT 
    l.product_id, 
	l.user_id,
    CASE WHEN b.product_id IS NOT NULL THEN 1 ELSE 0 END AS product_in_first_and_last
FROM (SELECT DISTINCT opp.product_id, o.user_id FROM order_products_prior opp
		INNER JOIN orders o USING(order_id)) l
LEFT JOIN both_orders b ON l.product_id = b.product_id AND l.user_id = b.user_id;

-- For each user-product pair, calculates how many orders have passed 
-- since the user last purchased that product (recency, in orders rather than days)
WITH 

user_product_last AS (
SELECT o.user_id,
       opp.product_id,
       MAX(o.order_number) AS user_product_last_order_number
FROM orders o
INNER JOIN order_products_prior opp USING(order_id)
GROUP BY o.user_id, opp.product_id
),

user_max_order AS (
SELECT user_id,
       MAX(order_number) AS user_max_order_number
FROM orders
WHERE eval_set = 'prior'
GROUP BY user_id
)

SELECT upl.user_id,
       upl.product_id,
       (umo.user_max_order_number - upl.user_product_last_order_number) AS user_product_orders_since_last
FROM user_product_last upl
INNER JOIN user_max_order umo USING(user_id);

-- For each user-product pair, flags whether the product appeared in the 
-- user's most recent order (1 if yes, 0 if no)
WITH 

user_last_order AS (
SELECT o.user_id, opp.product_id
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
WHERE (o.user_id, o.order_number) IN (
        SELECT user_id, MAX(order_number)
        FROM orders
        WHERE eval_set = 'prior'
        GROUP BY user_id
    	)
)

SELECT 
    up.user_id,
    up.product_id,
    CASE WHEN ulo.product_id IS NOT NULL THEN 1 ELSE 0 END AS user_product_in_last_order
FROM (SELECT DISTINCT o.user_id, opp.product_id 
      FROM order_products_prior opp 
      INNER JOIN orders o USING(order_id)) up
LEFT JOIN user_last_order ulo 
    ON up.user_id = ulo.user_id AND up.product_id = ulo.product_id;

-- For each user-product, the length of the unbroken run of the user's most
-- recent consecutive orders that contained the product (current reorder streak).
WITH

user_max AS (
SELECT user_id, MAX(order_number) AS max_order_number
FROM orders
WHERE eval_set = 'prior'
GROUP BY user_id
),

product_orders AS (
SELECT o.user_id,
       opp.product_id,
       o.order_number,
       o.order_number
         - ROW_NUMBER() OVER (PARTITION BY o.user_id, opp.product_id ORDER BY o.order_number) AS grp
FROM orders o
INNER JOIN order_products_prior opp USING(order_id)
),

streak AS (
SELECT user_id,
       product_id,
       grp,
       COUNT(*) AS run_length,
	   MAX(order_number) AS run_end
FROM product_orders 
GROUP BY user_id, product_id, grp
)

SELECT s.user_id,
       s.product_id,
       s.run_length AS user_product_current_streak
FROM streak s
INNER JOIN user_max um USING(user_id)
WHERE s.run_end = um.max_order_number;

-- For each user-product pair, computes the product's order rate over the user's
-- first-half orders vs their second-half (positive = rising, negative = fading).
WITH

user_bounds AS (
SELECT user_id, MAX(order_number) AS max_order_number
FROM orders
WHERE eval_set = 'prior'
GROUP BY user_id
),

half_order_counts AS (
SELECT o.user_id,
       COUNT(*) FILTER (WHERE o.order_number <= ub.max_order_number / 2.0) AS first_half_orders,
       COUNT(*) FILTER (WHERE o.order_number >  ub.max_order_number / 2.0) AS second_half_orders
FROM orders o
INNER JOIN user_bounds ub USING(user_id)
WHERE o.eval_set = 'prior'
GROUP BY o.user_id
),

product_half_counts AS (
SELECT o.user_id,
       opp.product_id,
       COUNT(*) FILTER (WHERE o.order_number <= ub.max_order_number / 2.0) AS first_half_product,
       COUNT(*) FILTER (WHERE o.order_number >  ub.max_order_number / 2.0) AS second_half_product
FROM orders o
INNER JOIN order_products_prior opp USING(order_id)
INNER JOIN user_bounds ub USING(user_id)
GROUP BY o.user_id, opp.product_id
)

SELECT phc.user_id,
       phc.product_id,
       phc.second_half_product::NUMERIC / NULLIF(hoc.second_half_orders, 0)
         - phc.first_half_product::NUMERIC / NULLIF(hoc.first_half_orders, 0) AS user_product_order_trend
FROM product_half_counts phc
INNER JOIN half_order_counts hoc USING(user_id);

-- Calculates the days since user last ordered this specific product
WITH 

last_product_order AS (
SELECT o.user_id,
       opp.product_id,
       MAX(o.order_number) AS last_product_order_number
FROM orders o
INNER JOIN order_products_prior opp USING(order_id)
GROUP BY o.user_id, opp.product_id
),

cumulative_days AS (
SELECT user_id,
       order_number,
       SUM(COALESCE(days_since_prior_order, 0)) 
            OVER (PARTITION BY user_id ORDER BY order_number) AS cumulative_days
FROM orders
WHERE eval_set = 'prior'
),

latest AS (
SELECT user_id, MAX(order_number) AS max_order_number 
FROM orders 
WHERE eval_set = 'prior' 
GROUP BY user_id
)

SELECT lpo.user_id,
       lpo.product_id,
       cd_last_overall.cumulative_days - cd_last_product.cumulative_days 
           AS user_product_days_since_last_order
FROM last_product_order lpo
INNER JOIN latest l USING(user_id)
INNER JOIN cumulative_days cd_last_overall 
    ON lpo.user_id = cd_last_overall.user_id 
    AND l.max_order_number = cd_last_overall.order_number
INNER JOIN cumulative_days cd_last_product 
    ON lpo.user_id = cd_last_product.user_id 
    AND lpo.last_product_order_number = cd_last_product.order_number;