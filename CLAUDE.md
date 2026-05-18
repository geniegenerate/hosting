# CLAUDE.md

Public marketing site + Apple/Google `.well-known/*` deep-link verification files for the GenieGenerate platform.

## Domains

- **Marketing root**: `https://www.geniegenerate.com` (live, 200). Apex `geniegenerate.com` resolves but returns 405 — assume www-redirect; never link the apex.
- **Deep-link verification subdomains** (one per environment):
  - prod: `link.geniegenerate.com`
  - staging: `staginglink.geniegenerate.com`
  - dev: `devlink.geniegenerate.com`

Cross-references: iOS `applinks:` in `mobile-app/ios/Runner/Info.plist`; Android `appHost` in `mobile-app/android/app/build.gradle.kts` per buildType.

## Scope (intentionally minimal)

This repo is a **static site**, deployed automatically by Cloudflare Pages on push to `main`. There is no dev server, no build step, no test suite, no container. Contents: `index.html`, `_redirects`, `images/`, `.well-known/apple-app-site-association`, `.well-known/assetlinks.json`.

**This is the only public repo** in the GenieGenerate org. Anything committed here is world-readable. Never put credentials, internal URLs, internal docs, or anything not intended for public visitors.

## Autonomous Loop (n/a for code, but verify-after-deploy is mandatory)

Skip the mobile/backend/admin fullstack loop here. The development loop is: edit → push → wait ~30s for Cloudflare Pages → curl-verify the live URL. Specifically:

- **No `docker compose`, no dev server, no test gate.** Cloudflare auto-deploys on push to `main`.
- **Verify after deploy** (this IS the done-gate for hosting):
  ```bash
  curl -sI https://www.geniegenerate.com/                                            # expect 200
  curl -s  https://www.geniegenerate.com/.well-known/apple-app-site-association | jq # expect JSON
  curl -s  https://www.geniegenerate.com/.well-known/assetlinks.json             | jq # expect JSON
  ```
- **Lane awareness**: this repo has no lane B. Work on `main` from `/Users/pinaet/Projects/geniegenerate/hosting/` only.

## ⚠️ Known issue (2026-05-18): AASA / assetlinks not served correctly

`curl https://www.geniegenerate.com/.well-known/apple-app-site-association` currently returns **404 (text/html)**, not the JSON in this repo. Likely cause: the `_redirects` line `/*  /index.html  200` is a catch-all rewrite that intercepts `.well-known/*` before Cloudflare's static handler can serve them. Fix candidates (untested):

1. Add explicit pass-through above the catch-all:
   ```
   /.well-known/*    /.well-known/:splat   200
   /*                /index.html           200
   ```
2. Or use Cloudflare Pages' `_headers` + ensure the files aren't being rewritten.

Until this is fixed, iOS Universal Links and Android App Links **will not verify in production**. Touch this only when ready to validate end-to-end with the mobile app — partial fixes can break passkey/webcredentials setup that depends on the same files. The webcredentials commit `3da1799` and Android App Links commit `4d20845` both predate this finding; both pushed without post-deploy verification.

## When working on `.well-known/` files

Deep-link verification files are load-bearing for iOS/Android app association. Before editing:

1. Read `mobile-app/CLAUDE.md` → Deep Linking conventions.
2. Confirm app bundle IDs against `mobile-app/ios/Runner.xcodeproj/project.pbxproj` and `mobile-app/android/app/build.gradle.kts`.
3. After push, validate live (curl commands above) and run Apple's [AASA validator](https://branch.io/resources/aasa-validator/).

## Git Workflow

Direct-push to `main`. Cloudflare Pages deploys automatically. Conventional commits. **Never** add Claude credit to commit messages. **Never** commit private content — this repo is public.
