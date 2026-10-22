"""
instacart_utils.py
 
Shared helper functions for the Instacart reorder-prediction notebooks
(v1 baseline model, v2 timing-feature experiment, ...).
 
Usage in a notebook (same folder):
    from instacart_utils import (
        mean_f1_per_order, select_by_expected_f1, per_user_predictions,
        basket_summary, basket_sizes, none_precision, feature_group,
    )
"""
 
import numpy as np
import pandas as pd
 
 
# ---------------------------------------------------------------------------
# Evaluation metric
# ---------------------------------------------------------------------------
 
def mean_f1_per_order(user_ids, y_true, y_pred):
    """Mean F1 per order (one train order per user), Kaggle-style.
 
    If a user reordered nothing AND nothing was predicted ('None' case),
    that user's F1 is 1.
    """
    d = pd.DataFrame({"user_id": user_ids, "y": y_true, "pred": y_pred})
    d["tp"] = d["y"] * d["pred"]
    g = d.groupby("user_id")[["tp", "pred", "y"]].sum()
 
    both_empty = (g["y"] == 0) & (g["pred"] == 0)
    f1 = np.where(
        both_empty,
        1.0,
        2 * g["tp"] / (g["pred"] + g["y"]).replace(0, np.nan),
    )
    return np.mean(f1)
 
 
# ---------------------------------------------------------------------------
# Per-user basket selection (expected-F1 maximisation)
# ---------------------------------------------------------------------------
 
def select_by_expected_f1(probs):
    """Select the products of ONE user that maximise the (approximate)
    expected F1, or predict 'None' (empty basket) if that is better.
 
    Requires calibrated probabilities (scale_pos_weight = 1).
    """
    order = np.argsort(-probs)                      # highest probability first
    p_sorted = probs[order]
    k = np.arange(1, len(p_sorted) + 1)
    exp_f1 = 2 * np.cumsum(p_sorted) / (k + p_sorted.sum())
    best_k = np.argmax(exp_f1) + 1
 
    pred = np.zeros(len(probs), dtype=int)
    p_none = np.prod(1 - probs)                     # P(user reorders nothing)
    if p_none > exp_f1[best_k - 1]:
        return pred                                 # predict 'None'
    pred[order[:best_k]] = 1
    return pred
 
 
def per_user_predictions(user_ids, proba):
    """Apply select_by_expected_f1 to every user. Returns a 0/1 array
    aligned with the input rows."""
    proba = np.asarray(proba)
    d = pd.DataFrame({"user_id": user_ids})
    pred = np.zeros(len(d), dtype=int)
    for idx in d.groupby("user_id").indices.values():   # row positions per user
        pred[idx] = select_by_expected_f1(proba[idx])
    return pred
 
 
# ---------------------------------------------------------------------------
# Analysis helpers
# ---------------------------------------------------------------------------
 
def basket_sizes(user_ids, y_pred):
    """Number of predicted products per user."""
    return pd.Series(y_pred).groupby(np.asarray(user_ids)).sum()
 
 
def basket_summary(user_ids, y_true, y_pred):
    """Average actual vs predicted basket size and 'None' rates."""
    d = pd.DataFrame({"user_id": user_ids, "y": y_true, "pred": y_pred})
    g = d.groupby("user_id")[["y", "pred"]].sum()
    return pd.Series({
        "avg_actual_reorders": g["y"].mean(),
        "avg_predicted_reorders": g["pred"].mean(),
        "users_with_no_predicted_reorders (%)": (g["pred"] == 0).mean() * 100,
        "users_with_no_actual_reorders (%)": (g["y"] == 0).mean() * 100,
    })
 
 
def none_precision(user_ids, y_true, y_pred):
    """Among users predicted as 'None', the share that truly reordered nothing."""
    d = pd.DataFrame({"user_id": user_ids, "y": y_true, "pred": y_pred})
    g = d.groupby("user_id")[["y", "pred"]].sum()
    predicted_none = g["pred"] == 0
    return (g.loc[predicted_none, "y"] == 0).mean()
 
 
def feature_group(name):
    """Map a feature name to its grain group (for feature-importance shares)."""
    if name == "user_share_of_product_orders":      # user-product grain despite the name
        return "user_product"
    for prefix in ["user_product_", "user_", "product_", "aisle_", "department_", "target_"]:
        if name.startswith(prefix):
            return prefix.rstrip("_")
    return "other"
 