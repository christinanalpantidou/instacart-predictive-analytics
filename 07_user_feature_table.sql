DROP TABLE IF EXISTS user_feature;

CREATE TABLE user_feature AS

WITH 
orders_table AS (
SELECT DISTINCT user_id
FROM orders
WHERE eval_set = 'prior'
),

basket AS (
SELECT sub.user_id,
		AVG(sub.basket_size) AS user_avg_basket_size,
		STDDEV(sub.basket_size) AS user_basket_size_stddev
FROM (SELECT o.user_id, 
		o.order_id, 
		COUNT(opp.product_id) AS basket_size
	  FROM orders o
	  INNER JOIN order_products_prior opp USING(order_id)
	  GROUP BY o.user_id, o.order_id) sub
GROUP BY sub.user_id
),

order_counts AS (
SELECT user_id, 
	COUNT(order_id) AS user_total_orders
FROM orders
WHERE eval_set = 'prior'
GROUP BY user_id
),

reorder_rate AS (
SELECT o.user_id, AVG(opp.reordered:: INT) AS user_reorder_rate
FROM orders o
INNER JOIN order_products_prior opp USING(order_id)
GROUP BY o.user_id
),

total_reorders AS (
SELECT o.user_id, COUNT(*) AS user_total_reorders
FROM orders o 
INNER JOIN order_products_prior opp USING(order_id)
WHERE opp.reordered = true
GROUP BY user_id
),

timing AS (
SELECT user_id,
		AVG(days_since_prior_order) AS user_avg_days_between_orders,
		MODE() WITHIN GROUP (ORDER BY order_dow) AS user_preferred_order_day,
		MODE() WITHIN GROUP (ORDER BY order_hour_of_day) AS user_preferred_order_hour,
		AVG(CASE WHEN order_hour_of_day BETWEEN 6 AND 11 THEN 1 ELSE 0 END) AS user_morning_order_rate,
		AVG(CASE WHEN order_hour_of_day BETWEEN 12 AND 17 THEN 1 ELSE 0 END) AS user_afternoon_order_rate,
		AVG(CASE WHEN order_hour_of_day BETWEEN 18 AND 20 THEN 1 ELSE 0 END) AS user_evening_order_rate,
		AVG(CASE WHEN order_hour_of_day BETWEEN 21 AND 23 
			OR order_hour_of_day BETWEEN 0 AND 5 THEN 1 ELSE 0 END) AS user_night_order_rate,
		AVG(CASE WHEN order_dow IN (0,6) THEN 1 ELSE 0 END) AS user_weekend_order_rate,
		AVG(CASE WHEN order_dow NOT IN (0,6) THEN 1 ELSE 0 END) AS user_weekday_order_rate,
		SUM(days_since_prior_order) AS user_total_days_active,
       (COUNT(order_id) - 1)::NUMERIC / NULLIF(SUM(days_since_prior_order) / 7.0, 0) AS user_orders_per_week,
	   (COUNT(order_id) - 1)::NUMERIC / NULLIF(SUM(days_since_prior_order), 0) AS user_order_frequency
FROM orders
WHERE eval_set = 'prior'
GROUP BY user_id
),

total_counts AS (
SELECT o.user_id,
        COUNT(DISTINCT p.department_id) AS user_unique_department_count,
		COUNT(DISTINCT p.aisle_id) AS user_unique_aisle_count,
        COUNT(DISTINCT opp.product_id) AS user_total_unique_products
FROM orders o
INNER JOIN order_products_prior opp USING(order_id)
INNER JOIN products p USING(product_id)
GROUP BY o.user_id
),

reordered_total AS (
SELECT o.user_id,
        COUNT(DISTINCT p.department_id) AS user_reordered_department_count,
		COUNT(DISTINCT p.aisle_id) AS user_reordered_aisle_count,
        COUNT(DISTINCT opp.product_id) AS user_reordered_unique_products
FROM orders o
INNER JOIN order_products_prior opp USING(order_id)
INNER JOIN products p USING(product_id)
WHERE opp.reordered = true
GROUP BY o.user_id
),

reorder_behaviour AS (
SELECT tc.*,
        COALESCE(rt.user_reordered_department_count, 0) AS user_reordered_department_count,
		COALESCE(rt.user_reordered_aisle_count, 0) AS user_reordered_aisle_count,
        COALESCE(rt.user_reordered_unique_products, 0) AS user_reordered_unique_products,
        COALESCE(rt.user_reordered_unique_products, 0):: NUMERIC / tc.user_total_unique_products AS user_reorder_diversity_rate
FROM total_counts tc
LEFT JOIN reordered_total rt USING(user_id)
),

last_products AS (
SELECT o.user_id, COUNT(opp.product_id) AS user_last_product_count
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
WHERE (o.user_id, o.order_number) IN (SELECT user_id, MAX(order_number)
    								  FROM orders
    								  WHERE eval_set = 'prior'
    								  GROUP BY user_id
									 )
GROUP BY o.user_id
),

first_products AS (
SELECT o.user_id, COUNT(opp.product_id) AS user_first_product_count
FROM orders o
INNER JOIN order_products_prior opp USING(order_id)
WHERE o.order_number = 1
GROUP BY o.user_id
),

firsts AS (
SELECT o.user_id, opp.product_id
		FROM orders o
		INNER JOIN order_products_prior opp USING(order_id)
		WHERE o.order_number = 1
),

first_second AS (
SELECT f.user_id, COUNT(DISTINCT f.product_id) AS user_products_in_first_and_second
FROM firsts f
WHERE (f.user_id, f.product_id) IN (SELECT o2.user_id, opp2.product_id
									FROM orders o2
									INNER JOIN order_products_prior opp2 USING(order_id)
									WHERE o2.order_number = 2)
GROUP BY f.user_id
),

last_orders AS (
SELECT o.user_id, opp.product_id
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
WHERE (o.user_id, o.order_number) IN (SELECT user_id, MAX(order_number)
        							  FROM orders
        							  WHERE eval_set = 'prior'
        							  GROUP BY user_id
    								  )
),

first_last AS (
SELECT l.user_id, 
		COUNT(l.product_id) AS user_products_in_first_and_last
FROM (SELECT user_id, product_id FROM last_orders
	  INTERSECT
	  SELECT user_id, product_id FROM firsts) l
GROUP BY l.user_id
)

SELECT ot.user_id,
		b.user_avg_basket_size,
		b.user_basket_size_stddev,
		oc.user_total_orders,
		rr.user_reorder_rate,
		COALESCE(tr.user_total_reorders, 0) AS user_total_reorders,
		t.user_avg_days_between_orders,
		t.user_preferred_order_day,
		t.user_preferred_order_hour,
		t.user_morning_order_rate,
		t.user_afternoon_order_rate,
		t.user_evening_order_rate,
		t.user_night_order_rate,
		t.user_weekend_order_rate,
		t.user_weekday_order_rate,
		t.user_total_days_active,
		t.user_orders_per_week,
		t.user_order_frequency,
		rb.user_unique_department_count,
		rb.user_unique_aisle_count,
		rb.user_total_unique_products,
		rb.user_reordered_department_count,
		rb.user_reordered_aisle_count,
		rb.user_reordered_unique_products,
		rb.user_reorder_diversity_rate,
		lp.user_last_product_count,
		fp.user_first_product_count,
		fsd.user_products_in_first_and_second,
		fl.user_products_in_first_and_last
FROM orders_table ot
LEFT JOIN basket b USING(user_id)
LEFT JOIN order_counts oc USING(user_id)
LEFT JOIN reorder_rate rr USING(user_id)
LEFT JOIN total_reorders tr USING(user_id)
LEFT JOIN timing t USING(user_id)
LEFT JOIN reorder_behaviour rb USING(user_id)
LEFT JOIN last_products lp USING(user_id)
LEFT JOIN first_products fp USING(user_id)
LEFT JOIN first_second fsd USING(user_id)
LEFT JOIN first_last fl USING(user_id);

DO $$
DECLARE
    table_rows BIGINT;
    expected   BIGINT;
BEGIN
    SELECT COUNT(*) INTO table_rows FROM user_feature;
    SELECT COUNT(DISTINCT user_id) INTO expected
    FROM orders WHERE eval_set = 'prior';

    IF table_rows <> expected THEN
        RAISE EXCEPTION 'user_feature grain violated: % rows, expected %',
            table_rows, expected;
    END IF;
END $$;