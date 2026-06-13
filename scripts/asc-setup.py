#!/usr/bin/env python3
"""Idempotent App Store Connect listing finisher for Pay Day.

Reads docs/asc-metadata.json and pushes the decided listing to ASC: app name +
subtitle + privacy URL (appInfoLocalization), Business/Finance categories
(appInfo relationships), and description/keywords/promo/URLs (the 1.0 version
localization), and sets MANUAL release. Re-runnable.

Pricing (free), availability (China off), and IAP/subscription creation are
handled by their own steps — see scripts/asc-products.py and the launch
checklist; the FIRST subscription submission needs a one-time web-UI product
selection per OPERATIONS.md.

Usage: python3 scripts/asc-setup.py
"""
import json
import os
import sys

sys.path.insert(0, os.path.expanduser("~/Dev/operator/lib"))
import asc  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = json.load(open(os.path.join(ROOT, "docs/asc-metadata.json")))
APP_ID = spec["appId"]


def first(path):
    return asc.get(path).get("data", [])


def main():
    info = first(f"/v1/apps/{APP_ID}/appInfos")
    info_id = info[0]["id"]
    state = info[0]["attributes"].get("appStoreState")
    print(f"appInfo {info_id} ({state})")

    # Categories (editable only while the app info is in an editable state).
    asc.patch(f"/v1/appInfos/{info_id}", {"data": {"type": "appInfos", "id": info_id,
        "relationships": {
            "primaryCategory": {"data": {"type": "appCategories", "id": spec["primaryCategory"]}},
            "secondaryCategory": {"data": {"type": "appCategories", "id": spec["secondaryCategory"]}}}}})
    print(f"  categories → {spec['primaryCategory']} / {spec['secondaryCategory']}")

    # Name + subtitle + privacy URL live on the appInfoLocalization.
    iloc = first(f"/v1/appInfos/{info_id}/appInfoLocalizations")
    iloc_id = next(l["id"] for l in iloc if l["attributes"].get("locale") == "en-US")
    asc.patch(f"/v1/appInfoLocalizations/{iloc_id}", {"data": {"type": "appInfoLocalizations",
        "id": iloc_id, "attributes": {
            "name": spec["name"], "subtitle": spec["subtitle"],
            "privacyPolicyUrl": spec["privacyPolicyUrl"]}}})
    print(f"  name/subtitle/privacy set ({iloc_id})")

    # Description / keywords / promo / URLs live on the version localization.
    vers = first(f"/v1/apps/{APP_ID}/appStoreVersions")
    ver = next(v for v in vers if v["attributes"].get("appStoreState") in
               ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"))
    ver_id = ver["id"]
    asc.patch(f"/v1/appStoreVersions/{ver_id}", {"data": {"type": "appStoreVersions",
        "id": ver_id, "attributes": {"releaseType": "MANUAL"}}})
    vloc = first(f"/v1/appStoreVersions/{ver_id}/appStoreVersionLocalizations")
    vloc_id = next(l["id"] for l in vloc if l["attributes"].get("locale") == "en-US")
    asc.patch(f"/v1/appStoreVersionLocalizations/{vloc_id}", {"data": {
        "type": "appStoreVersionLocalizations", "id": vloc_id, "attributes": {
            "description": spec["description"], "keywords": spec["keywords"],
            "promotionalText": spec["promotionalText"],
            "supportUrl": spec["supportUrl"], "marketingUrl": spec["marketingUrl"]}}})
    print(f"  version {ver['attributes'].get('versionString')} localization set ({vloc_id}); release=MANUAL")
    print("DONE")


if __name__ == "__main__":
    main()
