CREATE TABLE ml_dataset AS
WITH 
--  CTE1 selecting the variables from orders table
orders_table AS (
	SELECT 
		order_id,
		user_id,
		eval_set,
		order_number,
		order_dow,
		order_hour_of_day,
		COALESCE (days_since_prior_order, -1) AS days_since_prior_order
	FROM orders
),

--  CTE2 selecting the variables from products table
products_table AS(
	SELECT 
		p.product_id, 
		p.product_name,
		d.department_id,
		d.department, 
		a.aisle_id,
		a.aisle
	FROM products p
	INNER JOIN departments d USING(department_id)
	INNER JOIN aisles a USING(aisle_id)
),

--  CTE3 selecting the variables from prior orders table
prior_orders AS (
	SELECT 
		order_id,
		product_id,
		add_to_cart_order,
		reordered
	FROM order_products_prior
),

--  CTE4 selecting the target variable from the train table
train_table AS (
	SELECT 
		o.user_id,
		opt.product_id,
		opt.reordered AS target_variable
	FROM order_products_train opt
	INNER JOIN orders o USING(order_id)
)

SELECT 
	ot.*,
	pt.*,
	po.add_to_cart_order,
	po.reordered::INT AS reordered,
	CASE WHEN tt.target_variable IS NOT NULL THEN 1 ELSE 0 END AS target_variable
FROM orders_table ot
INNER JOIN prior_orders po USING(order_id)
INNER JOIN products_table pt USING(product_id)
LEFT JOIN train_table tt
	ON ot.user_id = tt.user_id AND po.product_id = tt.product_id;


UPDATE ml_dataset
SET days_since_prior_order = NULL
WHERE days_since_prior_order = -1;


ALTER TABLE ml_dataset
ALTER COLUMN reordered TYPE BOOLEAN
USING (reordered = 1);