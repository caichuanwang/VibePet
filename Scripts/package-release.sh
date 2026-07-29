#!/usr/bin/env bash

set -euo pipefail

VERSION="${1:-0.2.0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${2:-${ROOT_DIR}/dist}"

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must use MAJOR.MINOR.PATCH format: ${VERSION}" >&2
    exit 2
fi

for tool in swift lipo plutil codesign ditto shasum; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "Required tool is unavailable: ${tool}" >&2
        exit 2
    fi
done

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vibepet-release.XXXXXX")"
cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

APP_DIR="${WORK_DIR}/VibePet.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
HELPERS_DIR="${MACOS_DIR}/Helpers"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
PLIST_PATH="${CONTENTS_DIR}/Info.plist"
ARCHIVE_NAME="VibePet-v${VERSION}-macos-universal.zip"
ARCHIVE_PATH="${OUTPUT_DIR}/${ARCHIVE_NAME}"

cd "${ROOT_DIR}"

echo "Building arm64 release products..."
swift build -c release --triple arm64-apple-macosx
ARM64_BIN_DIR="$(swift build -c release --triple arm64-apple-macosx --show-bin-path)"

echo "Building x86_64 release products..."
swift build -c release --triple x86_64-apple-macosx
X86_64_BIN_DIR="$(swift build -c release --triple x86_64-apple-macosx --show-bin-path)"

for product in VibePetApp VibePetHooks VibePetSetup; do
    if [[ ! -x "${ARM64_BIN_DIR}/${product}" || ! -x "${X86_64_BIN_DIR}/${product}" ]]; then
        echo "Missing release product for one or both architectures: ${product}" >&2
        exit 1
    fi
done

RESOURCE_BUNDLE="${ARM64_BIN_DIR}/VibePet_VibePetApp.bundle"
if [[ ! -d "${RESOURCE_BUNDLE}" ]]; then
    echo "Missing SwiftPM resource bundle: ${RESOURCE_BUNDLE}" >&2
    exit 1
fi

mkdir -p "${HELPERS_DIR}" "${RESOURCES_DIR}" "${OUTPUT_DIR}"

lipo -create \
    "${ARM64_BIN_DIR}/VibePetApp" \
    "${X86_64_BIN_DIR}/VibePetApp" \
    -output "${MACOS_DIR}/VibePetApp"
lipo -create \
    "${ARM64_BIN_DIR}/VibePetHooks" \
    "${X86_64_BIN_DIR}/VibePetHooks" \
    -output "${HELPERS_DIR}/VibePetHooks"
lipo -create \
    "${ARM64_BIN_DIR}/VibePetSetup" \
    "${X86_64_BIN_DIR}/VibePetSetup" \
    -output "${HELPERS_DIR}/VibePetSetup"
chmod 755 \
    "${MACOS_DIR}/VibePetApp" \
    "${HELPERS_DIR}/VibePetHooks" \
    "${HELPERS_DIR}/VibePetSetup"

ditto "${RESOURCE_BUNDLE}" "${RESOURCES_DIR}/VibePet_VibePetApp.bundle"
cp "${ROOT_DIR}/VibePetApp/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
cp "${ROOT_DIR}/LICENSE" "${RESOURCES_DIR}/LICENSE"

BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || printf '1')}"
if [[ ! "${BUILD_NUMBER}" =~ ^[0-9]+$ ]]; then
    echo "BUILD_NUMBER must contain digits only: ${BUILD_NUMBER}" >&2
    exit 2
fi

plutil -create xml1 "${PLIST_PATH}"
plutil -insert CFBundleDevelopmentRegion -string en "${PLIST_PATH}"
plutil -insert CFBundleDisplayName -string VibePet "${PLIST_PATH}"
plutil -insert CFBundleExecutable -string VibePetApp "${PLIST_PATH}"
plutil -insert CFBundleIconFile -string AppIcon.icns "${PLIST_PATH}"
plutil -insert CFBundleIdentifier -string com.caichuanwang.VibePet "${PLIST_PATH}"
plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "${PLIST_PATH}"
plutil -insert CFBundleName -string VibePet "${PLIST_PATH}"
plutil -insert CFBundlePackageType -string APPL "${PLIST_PATH}"
plutil -insert CFBundleShortVersionString -string "${VERSION}" "${PLIST_PATH}"
plutil -insert CFBundleVersion -string "${BUILD_NUMBER}" "${PLIST_PATH}"
plutil -insert LSMinimumSystemVersion -string 14.0 "${PLIST_PATH}"
plutil -insert NSHighResolutionCapable -bool true "${PLIST_PATH}"
plutil -lint "${PLIST_PATH}"

# Ad-hoc signing gives the archive a verifiable code structure without claiming
# Apple Developer ID trust. Gatekeeper will still treat the app as unnotarized.
codesign --force --sign - --timestamp=none "${HELPERS_DIR}/VibePetHooks"
codesign --force --sign - --timestamp=none "${HELPERS_DIR}/VibePetSetup"
codesign --force --sign - --timestamp=none "${MACOS_DIR}/VibePetApp"
codesign --force --sign - --timestamp=none "${APP_DIR}"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"

if [[ -e "${ARCHIVE_PATH}" ]]; then
    rm "${ARCHIVE_PATH}"
fi
ditto -c -k --sequesterRsrc --keepParent "${APP_DIR}" "${ARCHIVE_PATH}"

(
    cd "${OUTPUT_DIR}"
    shasum -a 256 "${ARCHIVE_NAME}" > SHA256SUMS
)

echo
echo "Created unsigned/not-notarized release artifacts:"
echo "  ${ARCHIVE_PATH}"
echo "  ${OUTPUT_DIR}/SHA256SUMS"
echo "The app is ad-hoc signed only; Gatekeeper trust warnings are expected."
