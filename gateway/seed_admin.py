"""Create DeerFlow's first admin account once the Gateway is listening.

A fresh DeerFlow has no accounts, and whoever reaches /setup first becomes
admin. On a public URL that window is a race, so this closes it at first boot
by calling the Gateway's own POST /api/v1/auth/initialize over loopback.

The endpoint is CSRF-exempt and allows requests with no Origin header, and it
answers 409 once an admin exists, which makes this safe to re-run on every
deploy. It never touches the users table directly.
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request

PORT = os.environ.get("PORT", "8001")
BASE = f"http://127.0.0.1:{PORT}"
EMAIL = os.environ.get("DEERFLOW_ADMIN_EMAIL", "").strip()
PASSWORD = os.environ.get("DEERFLOW_ADMIN_PASSWORD", "")
HEALTH_ATTEMPTS = 150  # ~5 minutes; first boot runs Postgres migrations
HEALTH_INTERVAL = 2


def log(message: str) -> None:
    print(f"[seed-admin] {message}", flush=True)


def wait_for_gateway() -> bool:
    for _ in range(HEALTH_ATTEMPTS):
        try:
            with urllib.request.urlopen(f"{BASE}/health", timeout=3) as response:
                if response.status == 200:
                    return True
        except Exception:
            pass
        time.sleep(HEALTH_INTERVAL)
    return False


def main() -> int:
    if not EMAIL or not PASSWORD:
        log("no admin credentials configured; skipping")
        return 0

    if not wait_for_gateway():
        log("Gateway did not become healthy in time; skipping (complete /setup manually)")
        return 0

    payload = json.dumps({"email": EMAIL, "password": PASSWORD}).encode("utf-8")
    request = urllib.request.Request(
        f"{BASE}/api/v1/auth/initialize",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            if response.status in (200, 201):
                log(f"admin account created for {EMAIL}")
                return 0
            log(f"unexpected status {response.status}")
            return 0
    except urllib.error.HTTPError as exc:
        if exc.code == 409:
            log("an admin already exists; nothing to do")
            return 0
        # Never print the response body: a validation error echoes the request.
        log(f"could not create the admin account (HTTP {exc.code}); complete /setup manually")
        return 0
    except Exception as exc:  # noqa: BLE001 - never take the Gateway down with us
        log(f"could not create the admin account ({type(exc).__name__}); complete /setup manually")
        return 0


if __name__ == "__main__":
    sys.exit(main())
