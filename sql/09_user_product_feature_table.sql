DROP TABLE IF EXISTS user_product_feature;

CREATE TABLE user_product_feature AS 
WITH

user_product_table AS (
SELECT DISTINCT o.user_id, opp.product_id
FROM orders o
INNER JOIN order_products_prior opp USING(order_id)
),

stats AS (
SELECT o.user_id,
	   opp.product_id,
	   AVG(opp.add_to_cart_order) AS user_product_avg_cart_position,
	   AVG(o.days_since_prior_order) AS user_product_order_tempo,
	   COUNT(*) AS user_product_order_count,
	   COUNT(*)/ SUM(COUNT(*)) OVER(PARTITION BY o.user_id) AS user_product_order_share,
	   COUNT(DISTINCT o.order_id) / 
		SUM(COUNT(o.order_id)) OVER(PARTITION BY opp.product_id) AS user_share_of_product_orders
FROM orders o
INNER JOIN order_products_prior opp USING(order_id)
GROUP BY o.user_id, opp.product_id
),

order_cumulative_days AS (
SELECT user_id, 
       order_number,
       SUM(COALESCE(days_since_prior_order, 0)) 
	   		OVER (PARTITION BY user_id ORDER BY order_number) AS cumulative_days
FROM orders
WHERE eval_set = 'prior'
),

user_product_first_last AS (
SELECT o.user_id, 
       opp.product_id,
	   COUNT(o.order_id) AS user_product_order_count,
	   MIN(o.order_number) AS first_order_number,
       MAX(o.order_number) AS last_order_number
FROM orders o
INNER JOIN order_products_prior opp USING(order_id)
GROUP BY o.user_id, opp.product_id
),

user_product_repurchases AS (
SELECT upl.user_id,
       upl.product_id,
       (ocd_last.cumulative_days - ocd_first.cumulative_days) AS user_product_days_from_first_to_last,
	   (ocd_last.cumulative_days - ocd_first.cumulative_days)::NUMERIC
           / NULLIF(upl.user_product_order_count - 1, 0) AS user_product_avg_repurchase_interval
FROM user_product_first_last upl
INNER JOIN order_cumulative_days ocd_first
    ON upl.user_id = ocd_first.user_id AND upl.first_order_number = ocd_first.order_number
INNER JOIN order_cumulative_days ocd_last
    ON upl.user_id = ocd_last.user_id AND upl.last_order_number = ocd_last.order_number
),

user_product_orders AS (
SELECT o.user_id, 
       opp.product_id,
       COUNT(o.order_id) AS user_product_order_count
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
),

user_product_first_purchase AS (
SELECT upo.user_id,
       upo.product_id,
       upo.user_product_order_count,
       upo.user_product_order_count::NUMERIC 
           / ut.user_total_order_count AS user_product_order_rate_overall,
	   (ut.user_max_order_number - upf.first_order_number + 1) AS user_product_orders_since_first_purchase,
       upo.user_product_order_count::NUMERIC 
           / (ut.user_max_order_number - upf.first_order_number + 1) AS user_product_order_rate_since_first
FROM user_product_orders upo
INNER JOIN user_product_first upf USING(user_id, product_id)
INNER JOIN user_totals ut USING(user_id)
),

first_order AS (
SELECT DISTINCT o.user_id, opp.product_id
			FROM order_products_prior opp
			INNER JOIN orders o USING(order_id)
			WHERE o.order_number = 1
),

user_product_first_reorder AS (
SELECT 
    o.user_id,
	opp.product_id,
    COUNT(*) AS user_product_reorder_after_first_count
FROM order_products_prior opp
INNER JOIN orders o USING(order_id)
INNER JOIN first_order fo 
	ON o.user_id = fo.user_id 
		AND opp.product_id = fo.product_id
WHERE opp.reordered = true
GROUP BY o.user_id, opp.product_id
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
),

first_last AS (
SELECT 
    l.user_id, 
	l.product_id,
    CASE WHEN b.product_id IS NOT NULL THEN 1 ELSE 0 END AS user_product_in_first_and_last
FROM (SELECT DISTINCT opp.product_id, o.user_id FROM order_products_prior opp
		INNER JOIN orders o USING(order_id)) l
LEFT JOIN both_orders b ON l.product_id = b.product_id AND l.user_id = b.user_id
),

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
),

user_product_recency AS (
SELECT upl.user_id,
       upl.product_id,
       (umo.user_max_order_number - upl.user_product_last_order_number) AS user_product_orders_since_last
FROM user_product_last upl
INNER JOIN user_max_order umo USING(user_id)
),

user_product_in_last AS (
SELECT 
    up.user_id,
    up.product_id,
    CASE WHEN lo.product_id IS NOT NULL THEN 1 ELSE 0 END AS user_product_in_last_order
FROM (SELECT DISTINCT o.user_id, opp.product_id 
      FROM order_products_prior opp 
      INNER JOIN orders o USING(order_id)) up
LEFT JOIN last_order lo 
    ON up.user_id = lo.user_id AND up.product_id = lo.product_id
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
),

user_product_streak AS (
SELECT s.user_id,
       s.product_id,
       s.run_length AS user_product_current_streak
FROM streak s
INNER JOIN user_max_order umo USING(user_id)
WHERE s.run_end = umo.user_max_order_number
),

half_order_counts AS (
SELECT o.user_id,
       COUNT(*) FILTER (WHERE o.order_number <= umo.user_max_order_number / 2.0) AS first_half_orders,
       COUNT(*) FILTER (WHERE o.order_number >  umo.user_max_order_number / 2.0) AS second_half_orders
FROM orders o
INNER JOIN user_max_order umo USING(user_id)
WHERE o.eval_set = 'prior'
GROUP BY o.user_id
),

product_half_counts AS (
SELECT o.user_id,
       opp.product_id,
       COUNT(*) FILTER (WHERE o.order_number <= umo.user_max_order_number / 2.0) AS first_half_product,
       COUNT(*) FILTER (WHERE o.order_number >  umo.user_max_order_number / 2.0) AS second_half_product
FROM orders o
INNER JOIN order_products_prior opp USING(order_id)
INNER JOIN user_max_order umo USING(user_id)
GROUP BY o.user_id, opp.product_id
),

user_product_trend AS (
SELECT phc.user_id,
       phc.product_id,
       phc.second_half_product::NUMERIC / NULLIF(hoc.second_half_orders, 0)
         - phc.first_half_product::NUMERIC / NULLIF(hoc.first_half_orders, 0) AS user_product_order_trend
FROM product_half_counts phc
INNER JOIN half_order_counts hoc USING(user_id)
),

user_product_days AS (
SELECT upl.user_id,
       upl.product_id,
       ocd_last_overall.cumulative_days - ocd_last_product.cumulative_days 
           AS user_product_days_since_last_order
FROM user_product_last upl
INNER JOIN user_max_order umo USING(user_id)
INNER JOIN order_cumulative_days ocd_last_overall 
    ON upl.user_id = ocd_last_overall.user_id 
    AND umo.user_max_order_number = ocd_last_overall.order_number
INNER JOIN order_cumulative_days ocd_last_product 
    ON upl.user_id = ocd_last_product.user_id 
    AND upl.user_product_last_order_number = ocd_last_product.order_number
)

SELECT upt.user_id, 
		upt.product_id,
		s.user_product_avg_cart_position,
	   	s.user_product_order_tempo,
	   	s.user_product_order_count,
	   	s.user_product_order_share,
	   	s.user_share_of_product_orders,
		CASE WHEN s.user_product_order_count >= 2 
				THEN upr.user_product_days_from_first_to_last
		END AS user_product_days_from_first_to_last,
	   	upr.user_product_avg_repurchase_interval,
       	upfp.user_product_order_rate_overall,
	   	upfp.user_product_orders_since_first_purchase,
       	upfp.user_product_order_rate_since_first,
		CASE WHEN fo.product_id IS NOT NULL THEN
				COALESCE(upfr.user_product_reorder_after_first_count, 0) 
		END AS user_product_reorder_after_first_count,
		fl.user_product_in_first_and_last,
		uprc.user_product_orders_since_last,
		upil.user_product_in_last_order,
		COALESCE(ups.user_product_current_streak, 0) AS user_product_current_streak,
		uptr.user_product_order_trend,
		upd.user_product_days_since_last_order
FROM user_product_table upt
LEFT JOIN stats s ON upt.user_id = s.user_id AND upt.product_id = s.product_id
LEFT JOIN user_product_repurchases upr ON upt.user_id = upr.user_id AND upt.product_id = upr.product_id
LEFT JOIN user_product_first_purchase upfp ON upt.user_id = upfp.user_id AND upt.product_id = upfp.product_id
LEFT JOIN first_order fo ON upt.user_id = fo.user_id AND upt.product_id = fo.product_id
LEFT JOIN user_product_first_reorder upfr ON upt.user_id = upfr.user_id AND upt.product_id = upfr.product_id
LEFT JOIN first_last fl ON upt.user_id = fl.user_id AND upt.product_id = fl.product_id
LEFT JOIN user_product_recency uprc ON upt.user_id = uprc.user_id AND upt.product_id = uprc.product_id
LEFT JOIN user_product_in_last upil ON upt.user_id = upil.user_id AND upt.product_id = upil.product_id
LEFT JOIN user_product_streak ups ON upt.user_id = ups.user_id AND upt.product_id = ups.product_id
LEFT JOIN user_product_trend uptr ON upt.user_id = uptr.user_id AND upt.product_id = uptr.product_id
LEFT JOIN user_product_days upd ON upt.user_id = upd.user_id AND upt.product_id = upd.product_id;


-- Ensures all user_product_feature logical constraints and domain rules hold
DO $$
DECLARE
    v_a BIGINT;
    v_b BIGINT;
BEGIN
    -- 1. Grain: exactly one row per (user_id, product_id)
    SELECT COUNT(*), COUNT(DISTINCT (user_id, product_id))
    INTO v_a, v_b
    FROM user_product_feature;
    IF v_a <> v_b THEN
        RAISE EXCEPTION 'Grain violation: % rows vs % distinct (user_id, product_id) pairs', v_a, v_b;
    END IF;

    -- 2. Coverage: row count = distinct user-product pairs in source data
    SELECT COUNT(*) INTO v_b
    FROM (SELECT DISTINCT o.user_id, opp.product_id
          FROM orders o
          INNER JOIN order_products_prior opp USING(order_id)) src;
    IF v_a <> v_b THEN
        RAISE EXCEPTION 'Coverage mismatch: table has % rows, source has % distinct pairs', v_a, v_b;
    END IF;

    -- 3. Cross-table: users must match user_feature exactly
    SELECT COUNT(DISTINCT user_id) INTO v_a FROM user_product_feature;
    SELECT COUNT(*) INTO v_b FROM user_feature;
    IF v_a <> v_b THEN
        RAISE EXCEPTION 'User set mismatch: % distinct users vs % rows in user_feature', v_a, v_b;
    END IF;

    SELECT COUNT(*) INTO v_a
    FROM (SELECT DISTINCT user_id FROM user_product_feature) upf
    LEFT JOIN user_feature uf USING(user_id)
    WHERE uf.user_id IS NULL;
    IF v_a > 0 THEN
        RAISE EXCEPTION '% users in user_product_feature missing from user_feature', v_a;
    END IF;

    -- 4. Cross-table: every product must exist in product_feature
    SELECT COUNT(*) INTO v_a
    FROM (SELECT DISTINCT product_id FROM user_product_feature) upf
    LEFT JOIN product_feature pf USING(product_id)
    WHERE pf.product_id IS NULL;
    IF v_a > 0 THEN
        RAISE EXCEPTION '% products in user_product_feature missing from product_feature', v_a;
    END IF;

    -- 5. Rate bounds: all rates/shares in (0, 1]
    SELECT COUNT(*) INTO v_a
    FROM user_product_feature
    WHERE user_product_order_rate_overall    <= 0 OR user_product_order_rate_overall    > 1
       OR user_product_order_rate_since_first <= 0 OR user_product_order_rate_since_first > 1
       OR user_product_order_share            <= 0 OR user_product_order_share            > 1
       OR user_share_of_product_orders        <= 0 OR user_share_of_product_orders        > 1;
    IF v_a > 0 THEN
        RAISE EXCEPTION '% rows with rate/share outside (0, 1]', v_a;
    END IF;

    -- 6. Partition constraint: order shares sum to 1 per user
    SELECT COUNT(*) INTO v_a
    FROM (SELECT user_id, SUM(user_product_order_share) AS s
          FROM user_product_feature
          GROUP BY user_id) t
    WHERE ABS(s - 1) > 1e-9;
    IF v_a > 0 THEN
        RAISE EXCEPTION '% users whose user_product_order_share does not sum to 1', v_a;
    END IF;

    -- 7. Recency consistency: orders_since_last = 0  <=>  in_last_order = 1
    SELECT COUNT(*) INTO v_a
    FROM user_product_feature
    WHERE (user_product_orders_since_last = 0) <> (user_product_in_last_order = 1);
    IF v_a > 0 THEN
        RAISE EXCEPTION '% rows where orders_since_last and in_last_order disagree', v_a;
    END IF;

    -- 8. NULL discipline on the span: NULL iff single purchase
    SELECT COUNT(*) INTO v_a
    FROM user_product_feature
    WHERE (user_product_order_count = 1 AND user_product_days_from_first_to_last IS NOT NULL)
       OR (user_product_order_count >= 2 AND user_product_days_from_first_to_last IS NULL);
    IF v_a > 0 THEN
        RAISE EXCEPTION '% rows violating NULL rule on days_from_first_to_last', v_a;
    END IF;

    -- 9. Internal consistency: interval * (n - 1) = span (when defined)
    SELECT COUNT(*) INTO v_a
    FROM user_product_feature
    WHERE user_product_order_count >= 2
      AND ABS(user_product_avg_repurchase_interval * (user_product_order_count - 1)
              - user_product_days_from_first_to_last) > 1e-9;
    IF v_a > 0 THEN
        RAISE EXCEPTION '% rows where repurchase interval and span disagree', v_a;
    END IF;

    -- 10. Domain bounds on counts and ordinal features
    SELECT COUNT(*) INTO v_a
    FROM user_product_feature
    WHERE user_product_order_count < 1
       OR user_product_order_count > user_product_orders_since_first_purchase
       OR user_product_current_streak < 0
       OR user_product_current_streak > user_product_order_count
       OR user_product_orders_since_last < 0
       OR user_product_days_since_last_order < 0
       OR (user_product_reorder_after_first_count IS NOT NULL
           AND user_product_reorder_after_first_count > user_product_order_count - 1)
       OR user_product_in_first_and_last NOT IN (0, 1)
       OR user_product_in_last_order NOT IN (0, 1);
    IF v_a > 0 THEN
        RAISE EXCEPTION '% rows with out-of-domain counts or flags', v_a;
    END IF;

    -- 11. Flag implication: in first AND last => in last order
    SELECT COUNT(*) INTO v_a
    FROM user_product_feature
    WHERE user_product_in_first_and_last = 1
      AND user_product_in_last_order = 0;
    IF v_a > 0 THEN
        RAISE EXCEPTION '% rows where in_first_and_last = 1 but in_last_order = 0', v_a;
    END IF;

    RAISE NOTICE 'user_product_feature: all validation checks passed';
END $$;