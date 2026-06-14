#!/usr/bin/env python3
"""Idempotent RevenueCat (v2) setup for Pay Day.

Creates the `pro` entitlement, imports the seven App Store products into the RC
project's app, attaches the access products (annual/monthly/lifetime) to `pro`,
and builds the `default` offering with $rc_annual / $rc_monthly / $rc_lifetime
packages. Reads RC_SECRET_PAYDAY from the environment.

Usage: source ~/.config/midgar/credentials.env && python3 scripts/rc-setup.py
"""
import os
import sys
import requests

KEY = os.environ["RC_SECRET_PAYDAY"]
PROJECT = "proj2e2e82e3"
BASE = "https://api.revenuecat.com/v2"
H = {"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}

PREFIX = "com.guitaripod.payday"
SUBS = [
    (f"{PREFIX}.pro.annual", "subscription", "Pay Day Pro (Annual)", "$rc_annual"),
    (f"{PREFIX}.pro.monthly", "subscription", "Pay Day Pro (Monthly)", "$rc_monthly"),
    # Lifetime intentionally dropped: the paywall sells only subscriptions, so a
    # lifetime non-consumable would be an unreachable IAP at review.
]
PACKS = [
    (f"{PREFIX}.credits.starter", "consumable", "30 Credits"),
    (f"{PREFIX}.credits.regular", "consumable", "110 Credits"),
    (f"{PREFIX}.credits.propack", "consumable", "300 Credits"),
    (f"{PREFIX}.credits.business", "consumable", "650 Credits"),
]


def get(path):
    r = requests.get(BASE + path, headers=H, timeout=30)
    r.raise_for_status()
    return r.json()


def post(path, body):
    r = requests.post(BASE + path, headers=H, json=body, timeout=30)
    if r.status_code >= 400:
        print(f"    ! {r.status_code} {path}: {r.text[:200]}")
        return None
    return r.json()


def items(path):
    return get(path).get("items", [])


def main():
    apps = items(f"/projects/{PROJECT}/apps")
    # Prefer the production App Store app; fall back to whatever exists (test store).
    app = next((a for a in apps if a.get("type") == "app_store"), apps[0])
    app_id = app["id"]
    print("app:", app_id, app.get("type"))

    # Entitlement `pro`
    ents = {e["lookup_key"]: e for e in items(f"/projects/{PROJECT}/entitlements")}
    if "pro" in ents:
        pro = ents["pro"]["id"]
        print("✓ entitlement pro exists")
    else:
        pro = post(f"/projects/{PROJECT}/entitlements", {"lookup_key": "pro", "display_name": "Pay Day Pro"})["id"]
        print("+ entitlement pro")

    # Products (dedup per-app: the same store_identifier can exist on both the
    # test-store and App Store apps in this project).
    existing = {p["store_identifier"]: p for p in items(f"/projects/{PROJECT}/products")
                if p.get("app_id") == app_id}
    ids = {}
    for sid, ptype, name, _pkg in SUBS + [(s, t, n, None) for s, t, n in PACKS]:
        if sid in existing:
            ids[sid] = existing[sid]["id"]
            print(f"  ✓ product {sid}")
            continue
        body = {"store_identifier": sid, "app_id": app_id, "type": ptype,
                "display_name": name, "title": name}
        # The `subscription` block is only valid for the simulated (test) store;
        # for the App Store, RC reads the duration from App Store Connect.
        if ptype == "subscription" and app.get("type") == "test_store":
            body["subscription"] = {"duration": "P1Y" if "annual" in sid else "P1M"}
        r = post(f"/projects/{PROJECT}/products", body)
        if r:
            ids[sid] = r["id"]
            print(f"  + product {sid}")

    # Attach access products to `pro`
    access = [ids[s] for s, _t, _n, _p in SUBS if s in ids]
    if access:
        post(f"/projects/{PROJECT}/entitlements/{pro}/actions/attach_products", {"product_ids": access})
        print(f"  attached {len(access)} products to pro")

    # `default` offering + packages
    offs = {o["lookup_key"]: o for o in items(f"/projects/{PROJECT}/offerings")}
    if "default" in offs:
        off = offs["default"]["id"]
        print("✓ offering default exists")
    else:
        off = post(f"/projects/{PROJECT}/offerings", {"lookup_key": "default", "display_name": "Pay Day Pro"})["id"]
        print("+ offering default")

    existing_pkgs = {p["lookup_key"]: p for p in items(f"/projects/{PROJECT}/offerings/{off}/packages")}
    for sid, _t, _n, pkg_key in SUBS:
        if sid not in ids:
            continue
        if pkg_key in existing_pkgs:
            pkg = existing_pkgs[pkg_key]["id"]
        else:
            r = post(f"/projects/{PROJECT}/offerings/{off}/packages",
                     {"lookup_key": pkg_key, "display_name": pkg_key})
            if not r:
                continue
            pkg = r["id"]
            print(f"  + package {pkg_key}")
        post(f"/projects/{PROJECT}/packages/{pkg}/actions/attach_products",
             {"products": [{"product_id": ids[sid], "eligibility_criteria": "all"}]})

    # Consumable credit packs must also be packages in the offering — AICredits
    # prices packs from offering packages (availablePackages), so without these
    # the credit store shows packs with no price and can't purchase them.
    for sid, _t, name in PACKS:
        if sid not in ids:
            continue
        pkg_key = sid.split(".")[-1]
        if pkg_key in existing_pkgs:
            pkg = existing_pkgs[pkg_key]["id"]
        else:
            r = post(f"/projects/{PROJECT}/offerings/{off}/packages",
                     {"lookup_key": pkg_key, "display_name": name})
            if not r:
                continue
            pkg = r["id"]
            print(f"  + package {pkg_key}")
        post(f"/projects/{PROJECT}/packages/{pkg}/actions/attach_products",
             {"products": [{"product_id": ids[sid], "eligibility_criteria": "all"}]})
    print("DONE")


if __name__ == "__main__":
    main()
