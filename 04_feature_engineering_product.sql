-- Calculates the average reorder rate per product, 
--i.e. the proportion of times a product was ordered as a reorder
SELECT product_id, AVG(reordered:: INT) AS product_reorder_rate
FROM order_products_prior
GROUP BY product_id;

-- Counts the total number of times each product was ordered across all prior orders
SELECT product_id, COUNT(*) AS product_order_count
FROM order_products_prior
GROUP BY product_id;

-- Computes the average product order count for each aisle
SELECT opp.product_id,
       p.aisle_id,
       AVG(COUNT(*)) OVER(PARTITION BY p.aisle_id) AS aisle_avg_product_order_count
FROM order_products_prior opp
INNER JOIN products p USING(product_id)
GROUP BY opp.product_id, p.aisle_id;

-- Computes the average product order count for each department
SELECT opp.product_id,
       p.department_id,
       AVG(COUNT(*)) OVER(PARTITION BY p.department_id) AS department_avg_product_order_count
FROM order_products_prior opp
INNER JOIN products p USING(product_id)
GROUP BY opp.product_id, p.department_id;

-- Counts the total number of times each product was specifically reordered 
-- (not ordered for the first time)
SELECT product_id, COUNT(*) AS product_reorder_count
FROM order_products_prior
WHERE reordered = true
GROUP BY product_id;

-- Counts how many times each product appeared in a user's very first order
SELECT opp.product_id,
        COUNT(*) AS product_first_order_count
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
WHERE o.order_number = 1
GROUP BY opp.product_id;

-- Calculates the average number of days 
-- between orders for the orders in which each product appeared
SELECT opp.product_id, 
		AVG(o.days_since_prior_order) AS product_avg_days_between_orders
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
GROUP BY opp.product_id;

-- For each user-product pair, calculates the number of days elapsed between 
-- the first and last order containing that product (using each user's own 
-- cumulative order timeline), then aggregates up to product level to get 
-- the average active days span, ordering frequency, and orders per week
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
)

SELECT product_id, 
	   AVG(days_from_first_to_last) AS product_avg_days_from_first_to_last_order,
	   AVG(up_order_frequency) AS product_order_frequency,
       AVG(up_order_frequency) * 7 AS product_order_per_week
FROM user_product_frequency
GROUP BY product_id;

--Identifie	s the most frequently occurring day of the week on which each product is ordered
SELECT opp.product_id, 
		MODE() WITHIN GROUP (ORDER BY o.order_dow) AS product_preferred_order_day
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
GROUP BY opp.product_id;

-- Identifies the most frequently occurring hour of the day at which each product is ordered
SELECT opp.product_id, 
		MODE() WITHIN GROUP (ORDER BY o.order_hour_of_day) AS product_preferred_order_hour
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
GROUP BY opp.product_id;

-- Calculates the proportion of distinct users 
-- who reordered a product out of all users who ever ordered it
WITH

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
)

SELECT 
    tup.product_id,
    tup.product_unique_user_count,
    turp.product_unique_reorder_user_count,
    COALESCE(turp.product_unique_reorder_user_count, 0):: NUMERIC / tup.product_unique_user_count AS product_user_reorder_rate
FROM total_users_product tup
LEFT JOIN total_users_reordered_product turp USING(product_id);

-- Calculates the average position at which each product is added to the cart
SELECT product_id, 
	   AVG(add_to_cart_order) AS product_avg_cart_position
FROM order_products_prior
GROUP BY product_id;

-- Calculates the average position of each product relative to the basket size of the order
WITH 
order_basket_size AS (
SELECT order_id, COUNT(product_id) AS basket_size
FROM order_products_prior
GROUP BY order_id
)

SELECT opp.product_id,
       AVG(opp.add_to_cart_order::NUMERIC / obs.basket_size) AS product_avg_cart_position_relative_basket_size
FROM order_products_prior opp
INNER JOIN order_basket_size obs USING(order_id)
GROUP BY opp.product_id;

-- Calculates how often each product has been reordered from the aisles
WITH
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

both_tables AS (
SELECT ap.aisle_id,
		ap.aisle_product_count,
		arp.aisle_product_reordered_count,
		COALESCE(arp.aisle_product_reordered_count, 0):: NUMERIC / ap.aisle_product_count AS aisle_product_reorder_rate
FROM aisle_products ap
LEFT JOIN aisle_reordered_products arp USING(aisle_id)
)

SELECT p.product_id,
       bt.aisle_product_reorder_rate
FROM products p
LEFT JOIN both_tables bt USING(aisle_id);

-- Calculates how often each product has been ordered from the department
WITH
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

both_tables AS (
SELECT dp.department_id,
		dp.department_product_count,
		drp.department_product_reordered_count,
		COALESCE(drp.department_product_reordered_count, 0):: NUMERIC / dp.department_product_count AS department_product_reorder_rate
FROM department_products dp
LEFT JOIN department_reordered_products drp USING(department_id)
)

SELECT p.product_id,
       bt.department_product_reorder_rate
FROM products p
LEFT JOIN both_tables bt USING(department_id);
		
-- Counts how many times each product — having appeared in a first order
-- was subsequently reordered in any later order 
WITH 

first_order_products AS (
SELECT DISTINCT opp.product_id
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
WHERE o.order_number = 1
)

SELECT 
    opp.product_id,
    COUNT(*) AS product_first_order_reorder_count
FROM order_products_prior opp
INNER JOIN first_order_products fp USING(product_id)
WHERE opp.reordered = true
GROUP BY opp.product_id;

-- For each product, calculates the rate at which users 
-- who bought it in their first order went on to reorder it 
WITH 
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
)

SELECT product_id,
	product_first_order_user_count,
	product_first_order_reorder_user_count,
	COALESCE(product_first_order_reorder_user_count, 0):: NUMERIC / product_first_order_user_count AS product_first_order_reorder_rate
FROM first_order_reorders;

-- Counts the number of distinct users who ordered a given product 
-- in both their 1st and 2nd order
WITH 
first_order AS (
SELECT DISTINCT o.user_id, opp.product_id
FROM orders o
INNER JOIN order_products_prior opp USING(order_id)
WHERE o.order_number = 1
),

second_order AS (
SELECT DISTINCT o.user_id, opp.product_id
FROM orders o
INNER JOIN order_products_prior opp USING(order_id)
WHERE o.order_number = 2
)

SELECT product_id,
    	COUNT(DISTINCT user_id) AS product_repeat_user_count
FROM (SELECT user_id, product_id FROM first_order
		INTERSECT
		SELECT user_id, product_id FROM second_order)
GROUP BY product_id;

-- For each product, counts how many times it was added as the first item in the cart within 
-- a user's first-ever order, and calculates that count as a percentage of 
-- all such first-item placements across all products
SELECT opp.product_id, 
	COUNT(*) AS product_first_cart_first_order_count,
	COUNT(*) * 100.0 / SUM(COUNT(*)) OVER() AS product_first_cart_first_order_pct
FROM orders o
INNER JOIN order_products_prior opp USING(order_id)
WHERE o.order_number = 1 AND opp.add_to_cart_order = 1
GROUP BY opp.product_id;

-- For each product, counts the number of distinct users who added it 
-- as the first cart item in their first-ever order, and expresses that 
-- count as a percentage of all users who did the same across any product
SELECT opp.product_id,
	COUNT(o.user_id) AS product_first_cart_first_order_user_count,
	COUNT(o.user_id) * 100.0 / SUM(COUNT(o.user_id)) OVER() AS product_first_cart_first_order_user_pct
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
WHERE o.order_number = 1 AND opp.add_to_cart_order = 1
GROUP BY opp.product_id;

-- For each product, identifies all users who added it as the first item 
-- in their very first order, then checks how many of those same users 
-- went on to reorder it in any subsequent order. 
-- The final output returns both counts and the reorder rate as a ratio.
WITH 

first_order_product_users AS (
SELECT DISTINCT o.user_id, opp.product_id
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
WHERE opp.add_to_cart_order = 1 
AND o.order_number = 1
),

users_reorders AS (
SELECT DISTINCT o.user_id, opp.product_id
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
WHERE opp.reordered = true
),

first_and_reorder AS (
SELECT 
	fopu.product_id,
	COUNT(DISTINCT fopu.user_id) AS product_first_cart_first_order_user_count,
	COUNT(DISTINCT ur.user_id) AS product_first_order_reorder_user_count
FROM first_order_product_users fopu
LEFT JOIN users_reorders ur
	ON fopu.product_id = ur.product_id 
	AND fopu.user_id = ur.user_id
GROUP BY fopu.product_id
)

SELECT
    product_id,
    product_first_cart_first_order_user_count,
    product_first_order_reorder_user_count,
    COALESCE(product_first_order_reorder_user_count, 0)::NUMERIC / product_first_cart_first_order_user_count AS product_first_order_reorder_rate
FROM first_and_reorder;

-- For each product, flags whether it appeared in at least one user's first order 
-- AND in at least one user's last order returning 1 if both conditions are met, 0 otherwise
WITH 

first_order AS (
SELECT DISTINCT opp.product_id
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
WHERE o.order_number = 1
),

last_order AS (
SELECT DISTINCT opp.product_id
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
SELECT product_id FROM first_order
INTERSECT
SELECT product_id FROM last_order
)

SELECT 
    opp.product_id,
    CASE WHEN b.product_id IS NOT NULL THEN 1 ELSE 0 END AS product_in_first_and_last
FROM (SELECT DISTINCT product_id FROM order_products_prior) opp
LEFT JOIN both_orders b USING(product_id);

-- Calculates the number of users last orders in which each product was included
SELECT opp.product_id, COUNT(opp.order_id) AS product_last_orders_count
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
WHERE (o.user_id, o.order_number) IN (SELECT user_id, MAX(order_number)
										FROM orders 
										WHERE eval_set = 'prior'
										GROUP BY user_id
							         )
GROUP BY opp.product_id;

-- Counts the number of users who ordered a given product in both first and last order
WITH 

first_order AS (
SELECT DISTINCT o.user_id, opp.product_id
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
WHERE o.order_number = 1
),

last_order AS (
SELECT DISTINCT o.user_id, opp.product_id
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
    product_id,
    COUNT(user_id) AS product_users_in_first_and_last
FROM (SELECT user_id, product_id FROM first_order
	  INTERSECT
	  SELECT user_id, product_id FROM last_order) 
GROUP BY product_id;

-- Ranks each product by the orders in which it appeared, within each department and aisle
WITH

products_number AS(
SELECT product_id, COUNT(order_id) AS total_products_in_orders
FROM order_products_prior
GROUP BY product_id
)

SELECT pn.product_id,
	   DENSE_RANK() OVER(PARTITION BY p.department_id ORDER BY pn.total_products_in_orders DESC) AS department_product_popularity,
	   DENSE_RANK() OVER(PARTITION BY p.aisle_id ORDER BY pn.total_products_in_orders DESC) AS aisle_product_popularity
FROM products_number pn 
INNER JOIN products p USING(product_id);
