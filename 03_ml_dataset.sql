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


ALTER TABLE ml_dataset
DROP COLUMN target_variable;

-- Builds the final modeling table.
-- Grain:    one row per (user_id, product_id) pair from the prior history,
--           restricted to users who have a train order.
-- Features: prior history only (user_feature, product_feature, user_product_feature)
--           + context of the target (train) order that is known before checkout.
-- Target:   1 if the pair re-appears in the user's train order, 0 otherwise.
--           Products bought for the first time in the train order are out of scope.
 
DROP TABLE IF EXISTS ml_dataset_final;
 
CREATE TABLE ml_dataset_final AS
WITH
 
-- One row per train user: the order being predicted
train_orders AS (
SELECT user_id,
       order_id,
       order_dow              AS target_order_dow,
       order_hour_of_day      AS target_order_hour,
       days_since_prior_order AS target_days_since_prior_order
FROM orders
WHERE eval_set = 'train'
),
 
-- Positive examples: (user, product) pairs present in the train order
labels AS (
SELECT tro.user_id, opt.product_id
FROM order_products_train opt
INNER JOIN train_orders tro USING(order_id)
)
 
SELECT
-- Identifiers (excluded from X)
upf.user_id,
upf.product_id,
tro.order_id,
 
-- Target order context
tro.target_order_dow,
tro.target_order_hour,
tro.target_days_since_prior_order,
 
-- User features
uf.user_avg_basket_size,
uf.user_basket_size_stddev,
uf.user_total_orders,
uf.user_reorder_rate,
uf.user_total_reorders,
uf.user_preferred_order_day,
uf.user_preferred_order_hour,
uf.user_morning_order_rate,
uf.user_afternoon_order_rate,
uf.user_evening_order_rate,
uf.user_night_order_rate,
uf.user_weekend_order_rate,
uf.user_total_days_active,
uf.user_order_frequency,
uf.user_unique_department_count,
uf.user_unique_aisle_count,
uf.user_total_unique_products,
uf.user_reordered_department_count,
uf.user_reordered_aisle_count,
uf.user_reordered_unique_products,
uf.user_reorder_diversity_rate,
uf.user_last_product_count,
uf.user_first_product_count,
uf.user_products_in_first_and_second,
uf.user_products_in_first_and_last,
 
 -- Product features
pf.product_reorder_rate,
pf.product_order_count,
pf.aisle_avg_product_order_count,
pf.department_avg_product_order_count,
pf.product_reorder_count,
pf.product_avg_days_between_orders,
pf.product_avg_days_from_first_to_last_order,
pf.product_order_frequency,
pf.product_preferred_order_day,
pf.product_preferred_order_hour,
pf.product_unique_user_count,
pf.product_unique_reorder_user_count,
pf.product_user_reorder_rate,
pf.product_avg_cart_position,
pf.product_avg_cart_position_relative_basket_size,
pf.aisle_product_reorder_rate,
pf.department_product_reorder_rate,
pf.product_first_order_reorder_count,
pf.product_first_order_user_count,
pf.product_first_order_reorder_user_count,
pf.product_first_order_reorder_rate,
pf.product_repeat_user_count,
pf.product_first_cart_first_order_pct,
pf.product_first_cart_first_order_user_count,
pf.product_first_order_first_cart_reorder_user_count,
pf.product_first_order_first_cart_reorder_rate,
pf.product_in_first_and_last,
pf.product_last_orders_count,
pf.product_users_in_first_and_last,
pf.department_product_popularity,
pf.aisle_product_popularity,
 
 -- User-product features
upf.user_product_avg_cart_position,
upf.user_product_order_tempo,
upf.user_product_order_count,
upf.user_product_order_share,
upf.user_share_of_product_orders,
upf.user_product_days_from_first_to_last,
upf.user_product_avg_repurchase_interval,
upf.user_product_order_rate_overall,
upf.user_product_orders_since_first_purchase,
upf.user_product_order_rate_since_first,
upf.user_product_reorder_after_first_count,
upf.user_product_in_first_and_last,
upf.user_product_orders_since_last,
upf.user_product_in_last_order,
upf.user_product_current_streak,
upf.user_product_order_trend,
upf.user_product_days_since_last_order,
 
-- Target
CASE WHEN l.product_id IS NOT NULL THEN 1 ELSE 0 END AS target_variable
FROM user_product_feature upf
INNER JOIN train_orders tro
    ON upf.user_id = tro.user_id
INNER JOIN products p
    ON upf.product_id = p.product_id
LEFT JOIN user_feature uf
    ON upf.user_id = uf.user_id
LEFT JOIN product_feature pf
    ON upf.product_id = pf.product_id
LEFT JOIN labels l
    ON upf.user_id = l.user_id AND upf.product_id = l.product_id;
 
 
-- Ensures all ml_dataset_final logical constraints hold
DO $$
DECLARE
    v_rows BIGINT;
    v_a    BIGINT;
    v_b    BIGINT;
    v_rate NUMERIC;
BEGIN
-- 1. Source precondition: at most one train order per user
SELECT COUNT(*), COUNT(DISTINCT user_id) INTO v_a, v_b
FROM orders WHERE eval_set = 'train';
IF v_a <> v_b THEN
	RAISE EXCEPTION 'orders: % train orders for % distinct users', v_a, v_b;
END IF;
 
-- 2. Grain: one row per (user_id, product_id)
SELECT COUNT(*), COUNT(DISTINCT (user_id, product_id)) INTO v_rows, v_b
FROM ml_dataset_final;
IF v_rows <> v_b THEN
	RAISE EXCEPTION 'Grain violation: % rows vs % distinct pairs', v_rows, v_b;
END IF;
 
-- 3. Coverage: every prior pair of every train user, nothing else
SELECT COUNT(*) INTO v_b
FROM user_product_feature
WHERE user_id IN (SELECT user_id FROM orders WHERE eval_set = 'train');
IF v_rows <> v_b THEN
	RAISE EXCEPTION 'Coverage mismatch: % rows vs % expected pairs', v_rows, v_b;
END IF;
 
-- 4. No test users
SELECT COUNT(*) INTO v_a
FROM ml_dataset_final
WHERE user_id IN (SELECT user_id FROM orders WHERE eval_set = 'test');
IF v_a > 0 THEN
	RAISE EXCEPTION '% rows belong to test users', v_a;
END IF;
 
-- 5. Every user and product matched its feature table
SELECT COUNT(*) INTO v_a
FROM ml_dataset_final
WHERE user_total_orders IS NULL OR product_order_count IS NULL;
IF v_a > 0 THEN
	RAISE EXCEPTION '% rows with unmatched user or product features', v_a;
END IF;
 
-- 6. Target consistency: every reordered train item maps to exactly one positive row
SELECT SUM(target_variable) INTO v_a FROM ml_dataset_final;
SELECT COUNT(*) INTO v_b FROM order_products_train WHERE reordered = true;
IF v_a <> v_b THEN
	RAISE EXCEPTION 'Target mismatch: % positives vs % reordered train items', v_a, v_b;
END IF;
 
SELECT AVG(target_variable) INTO v_rate FROM ml_dataset_final;
   RAISE NOTICE 'ml_dataset_final: all checks passed — % rows, positive rate %',
       v_rows, ROUND(v_rate, 4);
END $$;