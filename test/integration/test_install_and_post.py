"""
Run the WordPress install wizard, log in, create a post, and verify it
appears on the public homepage. Idempotent — skips install if the site is
already configured.

Usage:
    BASE_URL=https://wordpress-dylan.dev.patterns.ordinaryexperts.com \
        python3 test_install_and_post.py
"""

import os
import sys
import time

import requests
from playwright.sync_api import sync_playwright

BASE_URL = os.environ.get("BASE_URL", "").rstrip("/")
ADMIN_USER = os.environ.get("WP_ADMIN_USER", "admin")
ADMIN_PASS = os.environ.get("WP_ADMIN_PASS", "OEPatterns!Test123")
ADMIN_EMAIL = os.environ.get("WP_ADMIN_EMAIL", "admin@example.com")
SITE_TITLE = "OE WordPress Smoke Test"
POST_TITLE = f"Smoke test post {int(time.time())}"
POST_BODY = "This is a smoke test post created by the integration runner."

if not BASE_URL:
    sys.exit("BASE_URL environment variable required")


def is_installed() -> bool:
    """Return True if WordPress is already installed (no install wizard)."""
    r = requests.get(f"{BASE_URL}/wp-login.php", timeout=15, allow_redirects=False)
    if r.status_code == 200 and "loginform" in r.text:
        return True
    if r.status_code in (301, 302):
        loc = r.headers.get("Location", "")
        if "install.php" in loc:
            return False
    r = requests.get(f"{BASE_URL}/", timeout=15, allow_redirects=True)
    return "install.php" not in r.url


def run_install(page) -> None:
    print(f"[install] visiting {BASE_URL}")
    page.goto(BASE_URL, wait_until="domcontentloaded", timeout=30000)
    if "install.php" not in page.url:
        page.goto(f"{BASE_URL}/wp-admin/install.php", wait_until="domcontentloaded", timeout=30000)
    if "language" in page.content():
        print("[install] language step")
        page.locator("select#language").select_option("")
        page.get_by_role("button", name="Continue").click()
        page.wait_for_load_state("domcontentloaded")
    print("[install] details step")
    page.locator("#weblog_title").fill(SITE_TITLE)
    page.locator("#user_login").fill(ADMIN_USER)
    page.locator("#pass1").fill(ADMIN_PASS)
    page.locator("#admin_email").fill(ADMIN_EMAIL)
    if page.locator("input[name='pw_weak']").count() > 0:
        page.locator("input[name='pw_weak']").check()
    page.get_by_role("button", name="Install WordPress").click()
    page.wait_for_load_state("domcontentloaded", timeout=60000)
    page_text = page.content()
    if "Success" not in page_text and "Log In" not in page_text:
        raise RuntimeError(f"Install did not appear to succeed. Page title: {page.title()}")
    print("[install] success")


def login(page) -> None:
    print("[login] visiting wp-login.php")
    page.goto(f"{BASE_URL}/wp-login.php", wait_until="networkidle", timeout=30000)
    user = page.locator("#user_login")
    pwd = page.locator("#user_pass")
    user.wait_for(state="visible", timeout=10000)
    pwd.wait_for(state="visible", timeout=10000)
    # Clear-then-type is more reliable than .fill() when autofill / focus
    # ordering can drop characters.
    user.click()
    user.press("Control+a")
    user.press("Delete")
    user.type(ADMIN_USER, delay=20)
    pwd.click()
    pwd.press("Control+a")
    pwd.press("Delete")
    pwd.type(ADMIN_PASS, delay=20)
    actual_user = user.input_value()
    actual_pwd = pwd.input_value()
    if actual_user != ADMIN_USER or actual_pwd != ADMIN_PASS:
        raise RuntimeError(
            f"Login fields didn't take values as expected: "
            f"user_login={actual_user!r} (wanted {ADMIN_USER!r}), "
            f"user_pass length={len(actual_pwd)} (wanted {len(ADMIN_PASS)})"
        )
    page.locator("#wp-submit").click()
    page.wait_for_url("**/wp-admin/**", timeout=30000)
    print(f"[login] landed on {page.url}")


def create_post(page) -> None:
    print(f"[post] creating '{POST_TITLE}'")
    page.goto(f"{BASE_URL}/wp-admin/post-new.php", wait_until="domcontentloaded", timeout=30000)
    page.wait_for_selector(".edit-post-layout, .editor-styles-wrapper, iframe[name='editor-canvas']", timeout=30000)
    # Dismiss welcome-guide via WP preferences API (most reliable across tour variants).
    page.evaluate("""
        () => {
            try {
                if (window.wp && window.wp.data) {
                    wp.data.dispatch('core/preferences').set('core/edit-post', 'welcomeGuide', false);
                }
            } catch (e) {}
        }
    """)
    page.keyboard.press("Escape")
    page.wait_for_timeout(500)
    # WP 6.x renders the editor canvas (title + body) inside an iframe.
    # Locate the title in whichever scope it lives in.
    iframe = page.locator("iframe[name='editor-canvas']")
    if iframe.count() > 0:
        scope = page.frame_locator("iframe[name='editor-canvas']")
        print("[post] editor canvas is inside iframe")
    else:
        scope = page
        print("[post] editor canvas is in main frame")
    title = scope.locator("[aria-label='Add title'], .editor-post-title__input, h1.editor-post-title").first
    title.wait_for(state="visible", timeout=15000)
    title.click()
    page.keyboard.type(POST_TITLE)
    page.keyboard.press("Tab")
    page.keyboard.type(POST_BODY)
    # Publish button lives in the top-bar toolbar (main frame, not iframe).
    page.locator(".editor-post-publish-button__button").click()
    confirm = page.locator(".editor-post-publish-panel .editor-post-publish-button")
    confirm.wait_for(state="visible", timeout=10000)
    confirm.click()
    page.locator(".editor-post-publish-panel__postpublish, .components-snackbar").first.wait_for(timeout=20000)
    print("[post] published")


def verify_public(page) -> None:
    print("[verify] loading public homepage")
    page.goto(BASE_URL, wait_until="domcontentloaded", timeout=30000)
    body = page.content()
    if POST_TITLE not in body:
        raise RuntimeError(f"Post title '{POST_TITLE}' not found on public homepage")
    print("[verify] post title visible on homepage")


def _run() -> None:
    """Drive the full flow against BASE_URL. Raises on any failure."""
    if is_installed():
        print(f"[install] already installed at {BASE_URL} — skipping wizard")
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        ctx = browser.new_context(viewport={"width": 1280, "height": 900})
        ctx.set_default_timeout(30000)
        page = ctx.new_page()
        try:
            if not is_installed():
                run_install(page)
            login(page)
            create_post(page)
            verify_public(page)
            print("ALL CHECKS PASSED")
        except Exception:
            try:
                page.screenshot(path="/code/test/integration/failure.png", full_page=True)
                print("Screenshot saved to test/integration/failure.png", file=sys.stderr)
            except Exception:
                pass
            raise
        finally:
            ctx.close()
            browser.close()


def test_install_and_post():
    """pytest entrypoint — invoked by `make test-integration`."""
    _run()


if __name__ == "__main__":
    try:
        _run()
        sys.exit(0)
    except Exception as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
