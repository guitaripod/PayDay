#!/usr/bin/env python3
"""Idempotent creation of Pay Day's IAP/subscription products in ASC.

Creates: subscription group "Pay Day Pro", the annual (7-day free trial) and
monthly subscriptions, the lifetime non-consumable, and four consumable credit
packs — each with an en-US localization and a USD base price. Skips anything
whose productId already exists, so it is safe to re-run.

NOTE (OPERATIONS.md): the FIRST product submission for an app with zero approved
products needs a one-time web-UI selection on the version. This script creates
and prices the products; final submission rides the version review.

Usage: python3 scripts/asc-products.py
"""
import os
import sys

sys.path.insert(0, os.path.expanduser("~/Dev/operator/lib"))
import asc  # noqa: E402

APP = "6779927672"
PREFIX = "com.guitaripod.payday"


def closest_point(points, target):
    best, bestd = None, 1e18
    for p in points:
        try:
            price = float(p["attributes"].get("customerPrice"))
        except (TypeError, ValueError):
            continue
        d = abs(price - target)
        if d < bestd:
            best, bestd = p, d
    return best


def existing_sub_groups():
    return asc.get(f"/v1/apps/{APP}/subscriptionGroups").get("data", [])


def existing_subs(group_id):
    return asc.get(f"/v1/subscriptionGroups/{group_id}/subscriptions").get("data", [])


def existing_iaps():
    return asc.paged(f"/v1/apps/{APP}/inAppPurchasesV2", **{"limit": "200"})


def ensure_group():
    for g in existing_sub_groups():
        if g["attributes"].get("referenceName") == "Pay Day Pro":
            return g["id"]
    r = asc.post("/v1/subscriptionGroups", {"data": {"type": "subscriptionGroups",
        "attributes": {"referenceName": "Pay Day Pro"},
        "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})
    return r["data"]["id"]


def try_(label, fn):
    try:
        fn()
        return True
    except Exception as e:
        print(f"    ! {label}: {str(e)[:160]}")
        return False


_TERRITORIES = None


def all_territories():
    global _TERRITORIES
    if _TERRITORIES is None:
        _TERRITORIES = [t["id"] for t in asc.paged("/v1/territories", **{"limit": "200"})]
    return _TERRITORIES


def price_subscription(sub_id, price):
    # ASC trap (OPERATIONS.md, psywave): subscription AVAILABILITY must be set
    # before a price — otherwise the price point relationship is rejected (409).
    try_("availability", lambda: asc.post("/v1/subscriptionAvailabilities", {"data": {
        "type": "subscriptionAvailabilities", "attributes": {"availableInNewTerritories": True},
        "relationships": {
            "subscription": {"data": {"type": "subscriptions", "id": sub_id}},
            "availableTerritories": {"data": [{"type": "territories", "id": t} for t in all_territories()]}}}}))
    pts = asc.paged(f"/v1/subscriptions/{sub_id}/pricePoints", **{"filter[territory]": "USA", "limit": "200"})
    pt = closest_point(pts, price)
    if not pt:
        print("    ! no USA price point found")
        return
    try_("price", lambda: asc.post("/v1/subscriptionPrices", {"data": {"type": "subscriptionPrices",
        "relationships": {
            "subscription": {"data": {"type": "subscriptions", "id": sub_id}},
            "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": pt["id"]}}}}}))


def ensure_subscription(group_id, product_id, ref, display, period, price, trial):
    subs = {s["attributes"]["productId"]: s for s in existing_subs(group_id)}
    if product_id in subs:
        sub_id = subs[product_id]["id"]
        print(f"  ✓ exists {product_id} — ensuring price/offer")
    else:
        r = asc.post("/v1/subscriptions", {"data": {"type": "subscriptions", "attributes": {
            "name": ref, "productId": product_id, "subscriptionPeriod": period,
            "familySharable": False, "groupLevel": 1},
            "relationships": {"group": {"data": {"type": "subscriptionGroups", "id": group_id}}}}})
        sub_id = r["data"]["id"]
        try_("localization", lambda: asc.post("/v1/subscriptionLocalizations", {"data": {
            "type": "subscriptionLocalizations", "attributes": {"locale": "en-US", "name": display},
            "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sub_id}}}}}))
        print(f"  + created {product_id} (${price}{' +7d trial' if trial else ''})")
    price_subscription(sub_id, price)
    if trial:
        # Intro offers are per-territory (the relationship 'territory' is required).
        ok = 0
        for t in all_territories():
            try:
                asc.post("/v1/subscriptionIntroductoryOffers", {"data": {
                    "type": "subscriptionIntroductoryOffers",
                    "attributes": {"offerMode": "FREE_TRIAL", "duration": "ONE_WEEK", "numberOfPeriods": 1},
                    "relationships": {
                        "subscription": {"data": {"type": "subscriptions", "id": sub_id}},
                        "territory": {"data": {"type": "territories", "id": t}}}}})
                ok += 1
            except Exception:
                pass
        print(f"    7-day free trial set in {ok} territories")
    return sub_id


def ensure_iap(product_id, ref, display, kind, price):
    by_pid = {i["attributes"]["productId"]: i for i in existing_iaps()}
    if product_id in by_pid:
        iap_id = by_pid[product_id]["id"]
        print(f"  ✓ exists {product_id} — ensuring price")
    else:
        r = asc.post("/v2/inAppPurchases", {"data": {"type": "inAppPurchases", "attributes": {
            "name": ref, "productId": product_id, "inAppPurchaseType": kind, "familySharable": False},
            "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})
        iap_id = r["data"]["id"]
        try_("localization", lambda: asc.post("/v1/inAppPurchaseLocalizations", {"data": {
            "type": "inAppPurchaseLocalizations",
            "attributes": {"locale": "en-US", "name": display, "description": display},
            "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}}}}))
        print(f"  + created {product_id} ({kind}, ${price})")
    pts = asc.paged(f"/v2/inAppPurchases/{iap_id}/pricePoints", **{"filter[territory]": "USA", "limit": "200"})
    pt = closest_point(pts, price)
    if pt:
        try_("price", lambda: asc.post("/v1/inAppPurchasePriceSchedules", {
            "data": {"type": "inAppPurchasePriceSchedules", "relationships": {
                "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${p}"}]}}},
            "included": [{"type": "inAppPurchasePrices", "id": "${p}",
                "attributes": {"startDate": None},
                "relationships": {"inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": pt["id"]}}}}]}))
    return iap_id


def main():
    print("Subscriptions:")
    gid = ensure_group()
    ensure_subscription(gid, f"{PREFIX}.pro.annual", "Pay Day Pro Annual", "Pay Day Pro (Annual)", "ONE_YEAR", 39.99, True)
    ensure_subscription(gid, f"{PREFIX}.pro.monthly", "Pay Day Pro Monthly", "Pay Day Pro (Monthly)", "ONE_MONTH", 4.99, False)
    print("Non-consumable:")
    ensure_iap(f"{PREFIX}.pro.lifetime", "Pay Day Pro Lifetime", "Pay Day Pro (Lifetime)", "NON_CONSUMABLE", 99.99)
    print("Consumable credit packs:")
    ensure_iap(f"{PREFIX}.credits.starter", "Credits Starter 30", "30 Credits", "CONSUMABLE", 2.99)
    ensure_iap(f"{PREFIX}.credits.regular", "Credits Regular 110", "110 Credits", "CONSUMABLE", 9.99)
    ensure_iap(f"{PREFIX}.credits.propack", "Credits Pro 300", "300 Credits", "CONSUMABLE", 24.99)
    ensure_iap(f"{PREFIX}.credits.business", "Credits Business 650", "650 Credits", "CONSUMABLE", 49.99)
    print("DONE")


if __name__ == "__main__":
    main()
