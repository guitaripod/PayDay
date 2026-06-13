#!/usr/bin/env python3
"""Upload Pay Day's 6.9" App Store screenshots to the 1.0 listing (en-US).

ASC asset flow per screenshot: reserve (POST /v1/appScreenshots → uploadOperations)
→ PUT the bytes to each operation → commit (PATCH uploaded=true + MD5 checksum).
Idempotent: skips the display set if it already has screenshots.

Usage: python3 scripts/asc-screenshots.py
"""
import hashlib
import os
import sys

import requests

sys.path.insert(0, os.path.expanduser("~/Dev/operator/lib"))
import asc  # noqa: E402

APP = "6779927672"
DISPLAY_TYPE = "APP_IPHONE_67"  # 6.5"/6.7"/6.9" family (1320×2868)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = [  # narrative order; screenshot 1 is the compliance hero
    "preview.png", "editor.png", "dashboard.png", "preview-ic.png", "paywall.png",
]


def version_localization():
    vers = asc.get(f"/v1/apps/{APP}/appStoreVersions").get("data", [])
    ver = next(v for v in vers if v["attributes"]["appStoreState"]
               in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "METADATA_REJECTED"))
    locs = asc.get(f"/v1/appStoreVersions/{ver['id']}/appStoreVersionLocalizations").get("data", [])
    return next(l["id"] for l in locs if l["attributes"]["locale"] == "en-US")


def screenshot_set(loc_id):
    sets = asc.get(f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets").get("data", [])
    for s in sets:
        if s["attributes"]["screenshotDisplayType"] == DISPLAY_TYPE:
            return s["id"]
    r = asc.post("/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets",
        "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
        "relationships": {"appStoreVersionLocalization": {
            "data": {"type": "appStoreVersionLocalizations", "id": loc_id}}}}})
    return r["data"]["id"]


def upload_one(set_id, path):
    data = open(path, "rb").read()
    name = os.path.basename(path)
    reserve = asc.post("/v1/appScreenshots", {"data": {"type": "appScreenshots",
        "attributes": {"fileSize": len(data), "fileName": name},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})
    shot_id = reserve["data"]["id"]
    for op in reserve["data"]["attributes"]["uploadOperations"]:
        headers = {h["name"]: h["value"] for h in op["requestHeaders"]}
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        resp = requests.request(op["method"], op["url"], headers=headers, data=chunk, timeout=120)
        resp.raise_for_status()
    asc.patch(f"/v1/appScreenshots/{shot_id}", {"data": {"type": "appScreenshots", "id": shot_id,
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    print(f"  + {name}")


def main():
    loc = version_localization()
    set_id = screenshot_set(loc)
    existing = asc.get(f"/v1/appScreenshotSets/{set_id}/appScreenshots").get("data", [])
    if existing:
        print(f"set {DISPLAY_TYPE} already has {len(existing)} screenshots — skipping")
        return
    for name in SHOTS:
        path = os.path.join(ROOT, "marketing/appstore", name)
        if os.path.exists(path):
            upload_one(set_id, path)
    print("DONE")


if __name__ == "__main__":
    main()
