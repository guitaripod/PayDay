#!/usr/bin/env python3
"""Attach an App Review screenshot to every Pay Day IAP and subscription.

IAPs/subscriptions sit in MISSING_METADATA until they carry a review screenshot.
Uses the paywall screenshot (it shows the products) for all of them. Same
reserve → PUT → commit flow as listing screenshots. Idempotent.

Usage: python3 scripts/asc-review-screenshots.py
"""
import hashlib
import os
import sys

import requests

sys.path.insert(0, os.path.expanduser("~/Dev/operator/lib"))
import asc  # noqa: E402

APP = "6779927672"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMG = os.path.join(ROOT, "marketing/appstore/paywall.png")


def upload(reserve_path, reserve_rel, commit_type):
    data = open(IMG, "rb").read()
    reserve = asc.post(reserve_path, {"data": {"type": commit_type,
        "attributes": {"fileSize": len(data), "fileName": "review-paywall.png"},
        "relationships": reserve_rel}})
    sid = reserve["data"]["id"]
    for op in reserve["data"]["attributes"]["uploadOperations"]:
        headers = {h["name"]: h["value"] for h in op["requestHeaders"]}
        requests.request(op["method"], op["url"], headers=headers,
                         data=data[op["offset"]:op["offset"] + op["length"]], timeout=120).raise_for_status()
    asc.patch(f"/v1/{commit_type}/{sid}", {"data": {"type": commit_type, "id": sid,
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})


def main():
    # Subscriptions
    groups = asc.get(f"/v1/apps/{APP}/subscriptionGroups").get("data", [])
    for g in groups:
        for s in asc.get(f"/v1/subscriptionGroups/{g['id']}/subscriptions").get("data", []):
            sid, pid = s["id"], s["attributes"]["productId"]
            existing = asc.get(f"/v1/subscriptions/{sid}/appStoreReviewScreenshot").get("data")
            if existing:
                print(f"  ✓ {pid} (sub) has review screenshot")
                continue
            upload("/v1/subscriptionAppStoreReviewScreenshots",
                   {"subscription": {"data": {"type": "subscriptions", "id": sid}}},
                   "subscriptionAppStoreReviewScreenshots")
            print(f"  + {pid} (sub)")

    # In-app purchases
    for i in asc.paged(f"/v1/apps/{APP}/inAppPurchasesV2", **{"limit": "50"}):
        iid, pid = i["id"], i["attributes"]["productId"]
        existing = asc.get(f"/v2/inAppPurchases/{iid}/appStoreReviewScreenshot").get("data")
        if existing:
            print(f"  ✓ {pid} (iap) has review screenshot")
            continue
        upload("/v1/inAppPurchaseAppStoreReviewScreenshots",
               {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iid}}},
               "inAppPurchaseAppStoreReviewScreenshots")
        print(f"  + {pid} (iap)")
    print("DONE")


if __name__ == "__main__":
    main()
