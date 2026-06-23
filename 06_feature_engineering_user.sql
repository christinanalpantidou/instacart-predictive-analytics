-- Calculates the number of products per order (basket size)
SELECT o.user_id, 
		o.order_id, 
		COUNT(opp.product_id) AS basket_size
FROM orders o 
INNER JOIN order_products_prior opp USING(order_id)
GROUP BY o.user_id, o.order_id;

-- Calculates the average basket size and it's standard deviation for each user
WITH 

user_orders AS (
SELECT o.user_id, 
		o.order_id, 
		COUNT(opp.product_id) AS basket_size
FROM orders o 
INNER JOIN order_products_prior opp USING(order_id)
GROUP BY o.user_id, o.order_id
)

SELECT user_id,
		AVG(basket_size) AS user_avg_basket_size,
		STDDEV(basket_size) AS user_basket_size_stddev
FROM user_orders
GROUP BY user_id;

-- Counts the total number of prior orders placed by each user
SELECT user_id, 
	COUNT(order_id) AS user_total_orders
FROM orders
WHERE eval_set = 'prior'
GROUP BY user_id;

-- Computes the average reorder rate per user, 
--i.e. the proportion of ordered items that were reorders.
SELECT o.user_id, AVG(opp.reordered:: INT) AS user_reorder_rate
FROM orders o
INNER JOIN order_products_prior opp USING(order_id)
GROUP BY o.user_id;

-- Counts the total number of reordered items per user across all prior orders
SELECT o.user_id, COUNT(*) AS user_total_reorders
FROM orders o 
INNER JOIN order_products_prior opp USING(order_id)
WHERE opp.reordered = true
GROUP BY user_id;

-- Calculates the average number of days elapsed between consecutive orders for each user
SELECT user_id, AVG(days_since_prior_order) AS user_avg_days_between_orders
FROM orders
WHERE eval_set = 'prior'
GROUP BY user_id;

-- Identifies the most frequently occurring day of the week on which each user places orders
SELECT user_id, MODE() WITHIN GROUP (ORDER BY order_dow) AS user_preferred_order_day
FROM orders
WHERE eval_set = 'prior'
GROUP BY user_id;

--  Identifies each user's most frequent order hour, 
-- and computes the share of orders placed in each time period 
-- (morning, afternoon, evening, night).
SELECT user_id, MODE() WITHIN GROUP (ORDER BY order_hour_of_day) AS user_preferred_order_hour,
	AVG(CASE WHEN order_hour_of_day BETWEEN 6 AND 11 THEN 1 ELSE 0 END) AS user_morning_order_rate,
	AVG(CASE WHEN order_hour_of_day BETWEEN 12 AND 17 THEN 1 ELSE 0 END) AS user_afternoon_order_rate,
	AVG(CASE WHEN order_hour_of_day BETWEEN 18 AND 20 THEN 1 ELSE 0 END) AS user_evening_order_rate,
	AVG(CASE WHEN order_hour_of_day BETWEEN 21 AND 23 
		OR order_hour_of_day BETWEEN 0 AND 5 THEN 1 ELSE 0 END) AS user_night_order_rate
FROM orders
WHERE eval_set = 'prior'
GROUP BY user_id;

--  Calculates the proportion of orders placed on weekends vs. weekdays for each user
SELECT user_id, 
    AVG(CASE WHEN order_dow IN (0,6) THEN 1 ELSE 0 END) AS user_weekend_order_rate,
	AVG(CASE WHEN order_dow NOT IN (0,6) THEN 1 ELSE 0 END) AS user_weekday_order_rate
FROM orders
WHERE eval_set = 'prior'
GROUP BY user_id;

-- Counts the total order days placed by each user and 
-- calculates the user orders per week
SELECT user_id,
       SUM(days_since_prior_order) AS user_total_days_active,
       (COUNT(order_id) - 1)::NUMERIC / NULLIF(SUM(days_since_prior_order) / 7.0, 0) AS user_orders_per_week
FROM orders
WHERE eval_set = 'prior'
GROUP BY user_id;

-- Computes the ordering frequency per user
SELECT user_id,
       (COUNT(order_id) - 1)::NUMERIC / NULLIF(SUM(days_since_prior_order), 0) AS user_order_frequency
FROM orders
WHERE eval_set = 'prior'
GROUP BY user_id;

-- Measures how diverse each user's reorder behaviour is, 
-- by comparing the number of distinct products, departments and aisles
-- they reordered against their total unique purchase history
WITH 

total AS (
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
)

SELECT t.*,
        rt.user_reordered_department_count,
		rt.user_reordered_aisle_count,
        COALESCE(rt.user_reordered_unique_products, 0) AS user_reordered_unique_products,
        COALESCE(rt.user_reordered_unique_products, 0):: NUMERIC / t.user_total_unique_products AS user_reorder_diversity_rate
FROM total t
LEFT JOIN reordered_total rt USING(user_id)
ORDER BY t.user_id;

-- Calculates the number of user's products in his last order
SELECT o.user_id, COUNT(opp.product_id) AS user_last_product_count
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
WHERE (o.user_id, o.order_number) IN (SELECT user_id, MAX(order_number)
    								  FROM orders
    								  WHERE eval_set = 'prior'
    								  GROUP BY user_id
									 )
GROUP BY o.user_id;

-- Calculates the number of user's products in his first order
SELECT o.user_id, COUNT(opp.product_id) AS user_first_product_count
FROM orders o
INNER JOIN order_products_prior opp USING(order_id)
WHERE o.order_number = 1
GROUP BY o.user_id;

-- For each user, calculates the number of products ordered in both his first and second order
WITH

firsts AS (
SELECT o.user_id, opp.product_id
FROM orders o
INNER JOIN order_products_prior opp USING(order_id)
WHERE o.order_number = 1
)

SELECT f.user_id, COUNT(DISTINCT f.product_id) AS user_products_in_first_and_second
FROM firsts f
WHERE (f.user_id, f.product_id) IN (SELECT o2.user_id, opp2.product_id
									FROM orders o2
									INNER JOIN order_products_prior opp2 USING(order_id)
									WHERE o2.order_number = 2)
GROUP BY f.user_id;

-- Counts the number of products appeared in both user's first and last order
WITH

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

first_orders AS (SELECT o.user_id, opp.product_id
FROM orders o 
INNER JOIN order_products_prior opp USING(order_id)
WHERE o.order_number = 1)

SELECT l.user_id, 
		COUNT(l.product_id) AS user_products_in_first_and_last
FROM (SELECT user_id, product_id FROM last_orders
	  INTERSECT
	  SELECT user_id, product_id FROM first_orders) l
GROUP BY l.user_id;
