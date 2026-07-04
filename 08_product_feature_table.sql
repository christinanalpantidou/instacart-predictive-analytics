DROP TABLE IF EXISTS product_feature;

CREATE TABLE product_feature AS 
WITH

products_table AS (
SELECT DISTINCT product_id
FROM order_products_prior
),

reorderRate_productCounts AS (
SELECT product_id, 
		AVG(reordered:: INT) AS product_reorder_rate,
		COUNT(*) AS product_order_count
FROM order_products_prior
GROUP BY product_id
),

aisle_average AS (
SELECT opp.product_id,
       AVG(COUNT(*)) OVER(PARTITION BY p.aisle_id) AS aisle_avg_product_order_count
FROM order_products_prior opp
INNER JOIN products p USING(product_id)
GROUP BY opp.product_id, p.aisle_id
),

department_average AS (
SELECT opp.product_id,
       AVG(COUNT(*)) OVER(PARTITION BY p.department_id) AS department_avg_product_order_count
FROM order_products_prior opp
INNER JOIN products p USING(product_id)
GROUP BY opp.product_id, p.department_id
),

reorder_count AS (
SELECT product_id, COUNT(*) AS product_reorder_count
FROM order_products_prior
WHERE reordered = true
GROUP BY product_id
),

first_order1 AS (
SELECT opp.product_id,
        COUNT(*) AS product_first_order_count
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
WHERE o.order_number = 1
GROUP BY opp.product_id
),

average_days AS (
SELECT opp.product_id, 
		AVG(o.days_since_prior_order) AS product_avg_days_between_orders
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
GROUP BY opp.product_id
),

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
),

user_product_days AS (
SELECT upl.user_id,
       upl.product_id,
	   upl.user_product_order_count,
       (ocd_last.cumulative_days - ocd_first.cumulative_days) AS days_from_first_to_last
FROM user_product_first_last upl
INNER JOIN order_cumulative_days ocd_first
   ON upl.user_id = ocd_first.user_id AND upl.first_order_number = ocd_first.order_number
   INNER JOIN order_cumulative_days ocd_last
   ON upl.user_id = ocd_last.user_id AND upl.last_order_number = ocd_last.order_number
),

user_product_frequency AS (
    SELECT user_id,
           product_id,
           days_from_first_to_last,
           (user_product_order_count - 1)::NUMERIC / NULLIF(days_from_first_to_last, 0) AS up_order_frequency
    FROM user_product_days
),

average_frequencies AS (
SELECT product_id, 
	   AVG(days_from_first_to_last) AS product_avg_days_from_first_to_last_order,
	   AVG(up_order_frequency) AS product_order_frequency,
       AVG(up_order_frequency) * 7 AS product_order_per_week
FROM user_product_frequency
GROUP BY product_id
),

preferred_hour_day AS (
SELECT opp.product_id, 
		MODE() WITHIN GROUP (ORDER BY o.order_dow) AS product_preferred_order_day,
		MODE() WITHIN GROUP (ORDER BY o.order_hour_of_day) AS product_preferred_order_hour
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
GROUP BY opp.product_id
),

total_users_product AS (
SELECT opp.product_id, 
        COUNT(DISTINCT o.user_id) AS product_unique_user_count
FROM order_products_prior opp
LEFT JOIN orders o USING(order_id)
GROUP BY opp.product_id
),

total_users_reordered_product AS (
SELECT opp.product_id,
        COUNT(DISTINCT o.user_id) AS product_unique_reorder_user_count
FROM order_products_prior opp
LEFT JOIN orders o USING(order_id)
WHERE opp.reordered = true
GROUP BY opp.product_id
),

product_unique AS (
SELECT 
    tup.product_id,
    tup.product_unique_user_count,
    turp.product_unique_reorder_user_count,
    COALESCE(turp.product_unique_reorder_user_count, 0):: NUMERIC / tup.product_unique_user_count AS product_user_reorder_rate
FROM total_users_product tup
LEFT JOIN total_users_reordered_product turp USING(product_id)
),

avg_cart_position AS (
SELECT product_id, 
	   AVG(add_to_cart_order) AS product_avg_cart_position
FROM order_products_prior
GROUP BY product_id
),

cartPosition_basketSize AS (
SELECT opp.product_id,
       AVG(opp.add_to_cart_order::NUMERIC / obs.basket_size) AS product_avg_cart_position_relative_basket_size
FROM order_products_prior opp
INNER JOIN (SELECT order_id, COUNT(product_id) AS basket_size
			FROM order_products_prior
			GROUP BY order_id
			) obs USING(order_id)
GROUP BY opp.product_id
),

aisle_products AS (
SELECT p.aisle_id, COUNT(opp.product_id) aisle_product_count
FROM products p
INNER JOIN order_products_prior opp USING(product_id)
GROUP BY p.aisle_id
),

aisle_reordered_products AS (
SELECT p.aisle_id, COUNT(opp.product_id) aisle_product_reordered_count
FROM products p
INNER JOIN order_products_prior opp USING(product_id)
WHERE opp.reordered = true
GROUP BY p.aisle_id
),

both_tables1 AS (
SELECT ap.aisle_id,
		ap.aisle_product_count,
		arp.aisle_product_reordered_count,
		COALESCE(arp.aisle_product_reordered_count, 0):: NUMERIC / ap.aisle_product_count AS aisle_product_reorder_rate
FROM aisle_products ap
LEFT JOIN aisle_reordered_products arp USING(aisle_id)
),

aisle_rate AS (
SELECT p.product_id,
       bt.aisle_product_reorder_rate
FROM products p
LEFT JOIN both_tables1 bt USING(aisle_id)
),

department_products AS (
SELECT p.department_id, COUNT(opp.product_id) department_product_count
FROM products p
INNER JOIN order_products_prior opp USING(product_id)
GROUP BY p.department_id
),

department_reordered_products AS (
SELECT p.department_id, COUNT(opp.product_id) department_product_reordered_count
FROM products p
INNER JOIN order_products_prior opp USING(product_id)
WHERE opp.reordered = true
GROUP BY p.department_id
),

both_tables2 AS (
SELECT dp.department_id,
		dp.department_product_count,
		drp.department_product_reordered_count,
		COALESCE(drp.department_product_reordered_count, 0):: NUMERIC / dp.department_product_count AS department_product_reorder_rate
FROM department_products dp
LEFT JOIN department_reordered_products drp USING(department_id)
),

department_rate AS (
SELECT p.product_id,
       bt.department_product_reorder_rate
FROM products p
LEFT JOIN both_tables2 bt USING(department_id)
),

first_reorder AS (
SELECT 
    opp.product_id,
    COUNT(*) AS product_first_order_reorder_count
FROM order_products_prior opp
INNER JOIN (SELECT DISTINCT opp.product_id
			FROM order_products_prior opp
			INNER JOIN orders o USING(order_id)
			WHERE o.order_number = 1
			)fp USING(product_id)
WHERE opp.reordered = true
GROUP BY opp.product_id
),

users_first_products AS (
SELECT DISTINCT o.user_id, opp.product_id
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
WHERE o.order_number = 1
),

users_reorders AS (
SELECT DISTINCT o.user_id, opp.product_id
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
WHERE opp.reordered = true
),

first_order_reorders AS (
SELECT 
    ufp.product_id,
    COUNT(DISTINCT ufp.user_id) AS product_first_order_user_count,
    COUNT(DISTINCT ur.user_id) AS product_first_order_reorder_user_count
FROM users_first_products ufp
LEFT JOIN users_reorders ur
    ON ufp.product_id = ur.product_id 
    AND ufp.user_id = ur.user_id
GROUP BY ufp.product_id
),

first_reorder_rate AS (
SELECT product_id,
	product_first_order_user_count,
	product_first_order_reorder_user_count,
	COALESCE(product_first_order_reorder_user_count, 0):: NUMERIC / product_first_order_user_count AS product_first_order_reorder_rate
FROM first_order_reorders
),

second_order AS (
SELECT DISTINCT o.user_id, opp.product_id
FROM orders o
INNER JOIN order_products_prior opp USING(order_id)
WHERE o.order_number = 2
),

first_and_second AS (
SELECT frse.product_id,
    	COUNT(DISTINCT frse.user_id) AS product_repeat_user_count
FROM (SELECT user_id, product_id FROM users_first_products
		INTERSECT
		SELECT user_id, product_id FROM second_order) frse
GROUP BY product_id
),

firstCart_firstOrder AS (
SELECT opp.product_id, 
	COUNT(*) AS product_first_cart_first_order_count,
	COUNT(*) * 100.0 / SUM(COUNT(*)) OVER() AS product_first_cart_first_order_pct
FROM orders o
INNER JOIN order_products_prior opp USING(order_id)
WHERE o.order_number = 1 AND opp.add_to_cart_order = 1
GROUP BY opp.product_id
),

firstCart_firstOrder_user AS (
SELECT opp.product_id,
	COUNT(o.user_id) * 100.0 / SUM(COUNT(o.user_id)) OVER() AS product_first_cart_first_order_user_pct
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
WHERE o.order_number = 1 AND opp.add_to_cart_order = 1
GROUP BY opp.product_id
),

first_order_product_users AS (
SELECT DISTINCT o.user_id, opp.product_id
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
WHERE opp.add_to_cart_order = 1 
AND o.order_number = 1
),

first_and_reorder AS (
SELECT 
	fopu.product_id,
	COUNT(DISTINCT fopu.user_id) AS product_first_cart_first_order_user_count,
	COUNT(DISTINCT ur.user_id) AS product_first_order_first_cart_reorder_user_count
FROM first_order_product_users fopu
LEFT JOIN users_reorders ur
	ON fopu.product_id = ur.product_id 
	AND fopu.user_id = ur.user_id
GROUP BY fopu.product_id
),

first_cart_order_rate AS (
SELECT
    product_id,
    product_first_cart_first_order_user_count,
    product_first_order_first_cart_reorder_user_count,
    COALESCE(product_first_order_first_cart_reorder_user_count, 0)::NUMERIC / product_first_cart_first_order_user_count AS product_first_order_first_cart_reorder_rate
FROM first_and_reorder
),

last_order3 AS (
SELECT DISTINCT o.user_id, opp.product_id
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
WHERE (o.user_id, o.order_number) IN (
        SELECT user_id, MAX(order_number)
        FROM orders
        WHERE eval_set = 'prior'
        GROUP BY user_id
    	)
),

first_order2 AS (
SELECT DISTINCT product_id
FROM users_first_products
),

last_order1 AS (
SELECT DISTINCT product_id
FROM last_order3
),

both_orders AS (
SELECT product_id FROM first_order2
INTERSECT
SELECT product_id FROM last_order1
),

first_and_last AS (
SELECT 
    opp.product_id,
    CASE WHEN b.product_id IS NOT NULL THEN 1 ELSE 0 END AS product_in_first_and_last
FROM (SELECT DISTINCT product_id FROM order_products_prior) opp
LEFT JOIN both_orders b USING(product_id)
),

last_order2 AS (
SELECT opp.product_id, COUNT(opp.order_id) AS product_last_orders_count
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
WHERE (o.user_id, o.order_number) IN (SELECT user_id, MAX(order_number)
										FROM orders 
										WHERE eval_set = 'prior'
										GROUP BY user_id
							         )
GROUP BY opp.product_id
),

first_last_count AS (
SELECT 
    frls.product_id,
    COUNT(frls.user_id) AS product_users_in_first_and_last
FROM (SELECT user_id, product_id FROM users_first_products
	  INTERSECT
	  SELECT user_id, product_id FROM last_order3) frls
GROUP BY product_id
),

products_number AS(
SELECT product_id, COUNT(order_id) AS total_products_in_orders
FROM order_products_prior
GROUP BY product_id
),

ranking AS (
SELECT pn.product_id,
	   DENSE_RANK() OVER(PARTITION BY p.department_id ORDER BY pn.total_products_in_orders DESC) AS department_product_popularity,
	   DENSE_RANK() OVER(PARTITION BY p.aisle_id ORDER BY pn.total_products_in_orders DESC) AS aisle_product_popularity
FROM products_number pn 
INNER JOIN products p USING(product_id)
)

SELECT pt.product_id,
		rrpc.product_reorder_rate,
		rrpc.product_order_count,
		aa.aisle_avg_product_order_count,
		da.department_avg_product_order_count,
		COALESCE(rc.product_reorder_count, 0) AS product_reorder_count,
		COALESCE(fo1.product_first_order_count, 0) AS product_first_order_count,
		ad.product_avg_days_between_orders,
		af.product_avg_days_from_first_to_last_order,
		af.product_order_frequency,
		af.product_order_per_week,
		phd.product_preferred_order_day,
		phd.product_preferred_order_hour,
		pu.product_unique_user_count,
		COALESCE(pu.product_unique_reorder_user_count, 0) AS product_unique_reorder_user_count,
		pu.product_user_reorder_rate,
		acp.product_avg_cart_position,
		cpbs.product_avg_cart_position_relative_basket_size,
		ar.aisle_product_reorder_rate,
		dr.department_product_reorder_rate,
		COALESCE(fr.product_first_order_reorder_count, 0) AS product_first_order_reorder_count,
		COALESCE(frr.product_first_order_user_count, 0) AS product_first_order_user_count,
		COALESCE(frr.product_first_order_reorder_user_count, 0) AS product_first_order_reorder_user_count,
		frr.product_first_order_reorder_rate,
		COALESCE(fas.product_repeat_user_count, 0) AS product_repeat_user_count,
		COALESCE(fcfo.product_first_cart_first_order_count, 0) AS product_first_cart_first_order_count,
		fcfo.product_first_cart_first_order_pct,
		fcfou.product_first_cart_first_order_user_pct,
		COALESCE(fcor.product_first_cart_first_order_user_count, 0) AS product_first_cart_first_order_user_count,
		COALESCE(fcor.product_first_order_first_cart_reorder_user_count, 0) AS product_first_order_first_cart_reorder_user_count,
		fcor.product_first_order_first_cart_reorder_rate,
		fal.product_in_first_and_last,
		COALESCE(lo2.product_last_orders_count, 0) AS product_last_orders_count,
		COALESCE(flc.product_users_in_first_and_last, 0) AS product_users_in_first_and_last,
		r.department_product_popularity,
		r.aisle_product_popularity
FROM products_table pt
LEFT JOIN reorderRate_productCounts rrpc USING(product_id)
LEFT JOIN aisle_average aa USING(product_id)
LEFT JOIN department_average da USING(product_id)
LEFT JOIN reorder_count rc USING(product_id)
LEFT JOIN first_order1 fo1 USING(product_id)
LEFT JOIN average_days ad USING(product_id)
LEFT JOIN average_frequencies af USING(product_id)
LEFT JOIN preferred_hour_day phd USING(product_id)
LEFT JOIN product_unique pu USING(product_id)
LEFT JOIN avg_cart_position acp USING(product_id)
LEFT JOIN cartPosition_basketSize cpbs USING(product_id)
LEFT JOIN aisle_rate ar USING(product_id)
LEFT JOIN department_rate dr USING(product_id)
LEFT JOIN first_reorder fr USING(product_id)
LEFT JOIN first_reorder_rate frr USING(product_id)
LEFT JOIN first_and_second fas USING(product_id)
LEFT JOIN firstCart_firstOrder fcfo USING(product_id)
LEFT JOIN firstCart_firstOrder_user fcfou USING(product_id)
LEFT JOIN first_cart_order_rate fcor USING(product_id)
LEFT JOIN first_and_last fal USING(product_id)
LEFT JOIN last_order2 lo2 USING(product_id)
LEFT JOIN first_last_count flc USING(product_id)
LEFT JOIN ranking r USING(product_id);

-- Ensures product_feature grain: one row per product_id
DO $$
DECLARE
    table_rows BIGINT;
    expected   BIGINT;
BEGIN
    SELECT COUNT(*) INTO table_rows FROM product_feature;
    SELECT COUNT(DISTINCT product_id) INTO expected
    FROM order_products_prior;

    IF table_rows <> expected THEN
        RAISE EXCEPTION 'product_feature grain violated: % rows, expected %',
            table_rows, expected;
    END IF;
END $$;

-- Ensures all product_feature logical constraints and domain rules hold
DO $$
DECLARE
    bad BIGINT;
BEGIN
    -- Subset counts cannot exceed their supersets
    SELECT COUNT(*) INTO bad FROM product_feature
    WHERE product_reorder_count > product_order_count
       OR product_first_order_count > product_order_count
       OR product_unique_reorder_user_count > product_unique_user_count
       OR product_first_order_reorder_user_count > product_first_order_user_count
       OR product_first_order_first_cart_reorder_user_count > product_first_cart_first_order_user_count
       OR product_repeat_user_count > product_first_order_user_count
       OR product_users_in_first_and_last > product_unique_user_count
       OR product_first_cart_first_order_user_count > product_first_order_user_count;
    IF bad > 0 THEN
        RAISE EXCEPTION 'product_feature: subset count invariant violated on % rows', bad;
    END IF;

    -- Rates must lie in [0, 1] (NULLs pass: comparison yields NULL, not TRUE)
    SELECT COUNT(*) INTO bad FROM product_feature
    WHERE product_reorder_rate NOT BETWEEN 0 AND 1
       OR product_user_reorder_rate NOT BETWEEN 0 AND 1
       OR product_first_order_reorder_rate NOT BETWEEN 0 AND 1
       OR product_first_order_first_cart_reorder_rate NOT BETWEEN 0 AND 1
       OR aisle_product_reorder_rate NOT BETWEEN 0 AND 1
       OR department_product_reorder_rate NOT BETWEEN 0 AND 1;
    IF bad > 0 THEN
        RAISE EXCEPTION 'product_feature: rate out of [0,1] on % rows', bad;
    END IF;

    -- Percentages must lie in [0, 100]
    SELECT COUNT(*) INTO bad FROM product_feature
    WHERE product_first_cart_first_order_pct NOT BETWEEN 0 AND 100
       OR product_first_cart_first_order_user_pct NOT BETWEEN 0 AND 100;
    IF bad > 0 THEN
        RAISE EXCEPTION 'product_feature: pct out of [0,100] on % rows', bad;
    END IF;

    -- Domain bounds
    SELECT COUNT(*) INTO bad FROM product_feature
    WHERE product_avg_cart_position < 1
       OR product_avg_cart_position_relative_basket_size NOT BETWEEN 0 AND 1
       OR product_in_first_and_last NOT IN (0, 1)
       OR product_preferred_order_day NOT BETWEEN 0 AND 6
       OR product_preferred_order_hour NOT BETWEEN 0 AND 23
       OR department_product_popularity < 1
       OR aisle_product_popularity < 1;
    IF bad > 0 THEN
        RAISE EXCEPTION 'product_feature: domain bound violated on % rows', bad;
    END IF;
END $$;
