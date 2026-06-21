#!/usr/bin/env bash
#
# VibePet — code signing & notarization (PLACEHOLDER, M6-7)
#
# Signing/notarization is intentionally DEFERRED to a separate release action
# (per the M6 scope decision: "APP 签名放在后面"). This script does NOT sign or
# notarize anything — it documents the steps and refuses to run so nobody mistakes
# it for a working pipeline. Fill in the credentials and remove the guard when the
# release action is set up.
#
# Prerequisites (when enabled):
#   - Apple Developer ID Application certificate in the login keychain
#   - A notarytool keychain profile:  xcrun notarytool store-credentials …
#   - A built, packaged VibePet.app
#
# Outline:
#   1. codesign --deep --force --options runtime \
#        --sign "Developer ID Application: <TEAM>" VibePet.app
#      # Sign the bundled helpers (VibePetHooks/VibePetSetup) too, then the .app.
#   2. ditto -c -k --keepParent VibePet.app VibePet.zip
#   3. xcrun notarytool submit VibePet.zip --keychain-profile "<PROFILE>" --wait
#   4. xcrun stapler staple VibePet.app
#   5. codesign --verify --deep --strict VibePet.app && spctl -a -vv VibePet.app

set -euo pipefail

echo "notarize.sh is a placeholder — signing/notarization is deferred (M6-7)." >&2
echo "See the commented outline in this file and docs/RELEASE-CHECKLIST.md." >&2
exit 1
