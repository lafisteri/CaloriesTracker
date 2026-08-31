#!/bin/bash
set -euo pipefail

# CaloriesTracker release pipeline:
# Xcode archive -> IPA -> GitHub Release -> AltStore source update

APP_NAME="CaloriesTracker"
SCHEME="CaloriesTracker"
CONFIGURATION="Release"
EXPECTED_BUNDLE_ID="com.caloriestracker.ios"
REMOTE="origin"
SOURCE_RELATIVE_PATH="altstore/source.json"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" ]]; then
  echo "ERROR: Run this script from inside the CaloriesTracker Git repository."
  exit 1
fi

PROJECT="$ROOT/CaloriesTracker.xcodeproj"
SOURCE_JSON="$ROOT/$SOURCE_RELATIVE_PATH"
ARTIFACTS_DIR="$ROOT/artifacts"
IPA_DIR="$ARTIFACTS_DIR/ipa"
LOG_DIR="$ARTIFACTS_DIR/logs"
WORK_DIR="$ARTIFACTS_DIR/.release-work"
DERIVED_DATA="$WORK_DIR/DerivedData"
ARCHIVE_PATH="$WORK_DIR/$APP_NAME.xcarchive"
PACKAGE_DIR="$WORK_DIR/package"

ASSUME_YES=0
NO_OPEN=0
VERSION_NOTES=""

usage() {
  cat <<USAGE
Usage: ./scripts/release.sh [options]

Options:
  -y, --yes           Skip the final confirmation prompt
      --no-open       Do not open Finder/GitHub after completion
      --notes TEXT    AltStore description for this version
  -h, --help          Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)
      ASSUME_YES=1
      ;;
    --no-open)
      NO_OPEN=1
      ;;
    --notes)
      [[ $# -ge 2 ]] || { echo "ERROR: --notes requires a value."; exit 1; }
      VERSION_NOTES="$2"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

fail() {
  echo
  echo "ERROR: $1"
  exit 1
}

step() {
  echo
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

cd "$ROOT"

step "Preflight"

for tool in git xcodebuild gh zip unzip shasum codesign ditto python3; do
  command -v "$tool" >/dev/null 2>&1 || fail "Required command not found: $tool"
done

[[ -d "$PROJECT" ]] || fail "Xcode project not found: $PROJECT"
[[ -f "$SOURCE_JSON" ]] || fail "AltStore source not found: $SOURCE_JSON"

python3 -m json.tool "$SOURCE_JSON" >/dev/null 2>&1 || fail "AltStore source is not valid JSON: $SOURCE_JSON"

gh auth status >/dev/null 2>&1 || fail "GitHub CLI is not authenticated. Run: gh auth login"
git remote get-url "$REMOTE" >/dev/null 2>&1 || fail "Git remote '$REMOTE' was not found."

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  git status --short
  fail "The Git working tree is not clean. Commit or stash changes before releasing."
fi

BRANCH="$(git symbolic-ref --quiet --short HEAD || true)"
[[ -n "$BRANCH" ]] || fail "Detached HEAD is not supported. Check out a branch first."

COMMIT="$(git rev-parse HEAD)"

mkdir -p "$IPA_DIR" "$LOG_DIR"
PROBE="$ARTIFACTS_DIR/.gitignore-probe"
touch "$PROBE"
if ! git check-ignore -q "$PROBE"; then
  rm -f "$PROBE"
  fail "The artifacts directory is not ignored. Add '/artifacts/' to the root .gitignore."
fi
rm -f "$PROBE"

REPO="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
IS_PRIVATE="$(gh repo view --json isPrivate --jq '.isPrivate')"

step "Read Xcode build settings"

BUILD_SETTINGS="$(
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=iOS' \
    -showBuildSettings
)"

VERSION="$(printf '%s\n' "$BUILD_SETTINGS" | awk -F ' = ' '$1 ~ /^[[:space:]]*MARKETING_VERSION$/ { print $2; exit }')"
BUILD="$(printf '%s\n' "$BUILD_SETTINGS" | awk -F ' = ' '$1 ~ /^[[:space:]]*CURRENT_PROJECT_VERSION$/ { print $2; exit }')"
BUNDLE_ID="$(printf '%s\n' "$BUILD_SETTINGS" | awk -F ' = ' '$1 ~ /^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER$/ { print $2; exit }')"
DEPLOYMENT_TARGET="$(printf '%s\n' "$BUILD_SETTINGS" | awk -F ' = ' '$1 ~ /^[[:space:]]*IPHONEOS_DEPLOYMENT_TARGET$/ { print $2; exit }')"

[[ -n "$VERSION" ]] || fail "MARKETING_VERSION could not be read from Xcode build settings."
[[ -n "$BUILD" ]] || fail "CURRENT_PROJECT_VERSION could not be read from Xcode build settings."
[[ "$BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" ]] || fail "Unexpected bundle identifier: $BUNDLE_ID"
[[ -n "$DEPLOYMENT_TARGET" ]] || fail "IPHONEOS_DEPLOYMENT_TARGET could not be read from Xcode build settings."

RELEASE_ID="${VERSION}.${BUILD}"
IPA_NAME="${APP_NAME}-${RELEASE_ID}.ipa"
SHA_NAME="${IPA_NAME}.sha256"
IPA_PATH="$IPA_DIR/$IPA_NAME"
SHA_PATH="$IPA_DIR/$SHA_NAME"
TAG="v${VERSION}-build.${BUILD}"
TITLE="${APP_NAME} ${VERSION} (${BUILD})"
LOG_PATH="$LOG_DIR/release-${RELEASE_ID}.log"
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/$IPA_NAME"
SOURCE_URL="https://raw.githubusercontent.com/$REPO/$BRANCH/$SOURCE_RELATIVE_PATH"

if [[ -z "$VERSION_NOTES" ]]; then
  VERSION_NOTES="${APP_NAME} ${VERSION} (${BUILD}) update."
fi

printf 'Repository:   %s\n' "$REPO"
printf 'Branch:       %s\n' "$BRANCH"
printf 'Commit:       %.12s\n' "$COMMIT"
printf 'Version:      %s\n' "$VERSION"
printf 'Build:        %s\n' "$BUILD"
printf 'Bundle ID:    %s\n' "$BUNDLE_ID"
printf 'Minimum iOS:  %s\n' "$DEPLOYMENT_TARGET"
printf 'Tag:          %s\n' "$TAG"
printf 'IPA:          %s\n' "$IPA_PATH"
printf 'AltStore:     %s\n' "$SOURCE_JSON"

git fetch --quiet --tags "$REMOTE"

if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
  fail "GitHub Release $TAG already exists. Increase the Xcode build number."
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
  TAG_COMMIT="$(git rev-list -n 1 "$TAG")"
  [[ "$TAG_COMMIT" == "$COMMIT" ]] || fail "Tag $TAG already points to a different commit. Increase the build number."
fi

python3 - "$SOURCE_JSON" "$EXPECTED_BUNDLE_ID" "$VERSION" "$BUILD" <<'PY'
import json
import sys

path, bundle_id, version, build = sys.argv[1:]
with open(path, encoding="utf-8") as f:
    source = json.load(f)

apps = [a for a in source.get("apps", []) if a.get("bundleIdentifier") == bundle_id]
if len(apps) != 1:
    raise SystemExit(f"ERROR: Expected exactly one AltStore app with bundleIdentifier {bundle_id}, found {len(apps)}")

for item in apps[0].get("versions", []):
    if str(item.get("version")) == version and str(item.get("buildVersion")) == build:
        raise SystemExit(f"ERROR: AltStore source already contains {version} ({build}). Increase the Xcode build number.")
PY

if [[ "$ASSUME_YES" -ne 1 ]]; then
  echo
  read -r -p "Archive, publish GitHub Release, and update AltStore source? [y/N] " ANSWER
  [[ "$ANSWER" =~ ^[Yy]$ ]] || {
    echo "Cancelled."
    exit 0
  }
fi

step "Check remote branch state"

git fetch --quiet "$REMOTE"
if git show-ref --verify --quiet "refs/remotes/$REMOTE/$BRANCH"; then
  read -r BEHIND AHEAD <<< "$(git rev-list --left-right --count "$REMOTE/$BRANCH...HEAD")"
  if [[ "$BEHIND" -gt 0 ]]; then
    fail "Local branch is behind $REMOTE/$BRANCH by $BEHIND commit(s). Pull/rebase before releasing."
  fi
fi

step "Create signed Xcode archive"

rm -rf "$WORK_DIR"
mkdir -p "$PACKAGE_DIR/Payload"

cleanup() {
  STATUS=$?
  if [[ "$STATUS" -eq 0 ]]; then
    rm -rf "$WORK_DIR"
  else
    echo
    echo "Release failed. Temporary work files were kept at:"
    echo "$WORK_DIR"
  fi
  exit "$STATUS"
}
trap cleanup EXIT

XCODE_ARGS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "generic/platform=iOS"
  -archivePath "$ARCHIVE_PATH"
  -derivedDataPath "$DERIVED_DATA"
  -allowProvisioningUpdates
  archive
)

if command -v xcbeautify >/dev/null 2>&1; then
  xcodebuild "${XCODE_ARGS[@]}" 2>&1 | tee "$LOG_PATH" | xcbeautify
else
  xcodebuild "${XCODE_ARGS[@]}" 2>&1 | tee "$LOG_PATH"
fi

[[ -d "$ARCHIVE_PATH" ]] || fail "Xcode archive was not created."

APPLICATIONS_DIR="$ARCHIVE_PATH/Products/Applications"
APP_COUNT="$(find "$APPLICATIONS_DIR" -maxdepth 1 -type d -name '*.app' | wc -l | tr -d '[:space:]')"
[[ "$APP_COUNT" == "1" ]] || fail "Expected exactly one .app in the archive; found $APP_COUNT."

APP_PATH="$(find "$APPLICATIONS_DIR" -maxdepth 1 -type d -name '*.app' -print -quit)"
APP_BUNDLE_NAME="$(basename "$APP_PATH")"
INFO_PLIST="$APP_PATH/Info.plist"
[[ -f "$INFO_PLIST" ]] || fail "Archived app Info.plist was not found."

ARCHIVE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
ARCHIVE_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
ARCHIVE_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
ARCHIVE_MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$INFO_PLIST" 2>/dev/null || true)"

[[ "$ARCHIVE_VERSION" == "$VERSION" ]] || fail "Archive version does not match preflight version."
[[ "$ARCHIVE_BUILD" == "$BUILD" ]] || fail "Archive build does not match preflight build."
[[ "$ARCHIVE_BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" ]] || fail "Archive bundle identifier changed unexpectedly."

if [[ -n "$ARCHIVE_MIN_OS" ]]; then
  MIN_OS_VERSION="$ARCHIVE_MIN_OS"
else
  MIN_OS_VERSION="$DEPLOYMENT_TARGET"
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

step "Validate AltStore permissions"

ENTITLEMENTS_PLIST="$WORK_DIR/entitlements.plist"
codesign -d --entitlements :- "$APP_PATH" > "$ENTITLEMENTS_PLIST" 2>/dev/null || true

python3 - "$SOURCE_JSON" "$EXPECTED_BUNDLE_ID" "$ENTITLEMENTS_PLIST" "$INFO_PLIST" <<'PY'
import json
import plistlib
import sys

source_path, bundle_id, entitlements_path, info_path = sys.argv[1:]

with open(source_path, encoding="utf-8") as f:
    source = json.load(f)
app = next(a for a in source["apps"] if a.get("bundleIdentifier") == bundle_id)
permissions = app.get("appPermissions", {})
source_entitlements = set(permissions.get("entitlements", []))

with open(entitlements_path, "rb") as f:
    raw_entitlements = plistlib.load(f)
ignored = {"application-identifier", "com.apple.developer.team-identifier"}
actual_entitlements = set(raw_entitlements) - ignored

if source_entitlements != actual_entitlements:
    print("ERROR: AltStore entitlement list no longer matches the archived app.", file=sys.stderr)
    print(f"Source: {sorted(source_entitlements)}", file=sys.stderr)
    print(f"Actual: {sorted(actual_entitlements)}", file=sys.stderr)
    print("Update altstore/source.json appPermissions before releasing.", file=sys.stderr)
    raise SystemExit(1)

with open(info_path, "rb") as f:
    info = plistlib.load(f)
privacy_keys = sorted(k for k in info if k.endswith("UsageDescription"))
source_privacy = permissions.get("privacy", {})

if privacy_keys and not source_privacy:
    print("ERROR: The app now declares privacy UsageDescription keys, but AltStore privacy permissions are empty.", file=sys.stderr)
    print(f"Info.plist keys: {privacy_keys}", file=sys.stderr)
    print("Update altstore/source.json appPermissions before releasing.", file=sys.stderr)
    raise SystemExit(1)
PY

step "Create IPA"

rm -f "$IPA_PATH" "$SHA_PATH"
ditto "$APP_PATH" "$PACKAGE_DIR/Payload/$APP_BUNDLE_NAME"

(
  cd "$PACKAGE_DIR"
  COPYFILE_DISABLE=1 zip -qry "$IPA_PATH" Payload
)

[[ -f "$IPA_PATH" ]] || fail "IPA was not created."
unzip -tq "$IPA_PATH" >/dev/null || fail "IPA ZIP integrity check failed."
unzip -Z1 "$IPA_PATH" | grep -q "^Payload/$APP_BUNDLE_NAME/Info.plist$" || fail "IPA does not contain the expected app bundle."

(
  cd "$IPA_DIR"
  shasum -a 256 "$IPA_NAME" > "$SHA_NAME"
)

IPA_SIZE_BYTES="$(wc -c < "$IPA_PATH" | tr -d '[:space:]')"
IPA_SIZE_HUMAN="$(du -h "$IPA_PATH" | awk '{ print $1 }')"
IPA_SHA="$(awk '{ print $1 }' "$SHA_PATH")"

echo "IPA created: $IPA_PATH"
echo "Size:        $IPA_SIZE_HUMAN ($IPA_SIZE_BYTES bytes)"
echo "SHA-256:     $IPA_SHA"

step "Push source commit"

git push "$REMOTE" "HEAD:refs/heads/$BRANCH"

step "Create and push Git tag"

if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
  git tag -a "$TAG" "$COMMIT" -m "$TITLE"
fi

git push "$REMOTE" "refs/tags/$TAG"

step "Create GitHub Release"

gh release create "$TAG" \
  "$IPA_PATH#${APP_NAME} IPA" \
  "$SHA_PATH#SHA-256 checksum" \
  -R "$REPO" \
  --verify-tag \
  --title "$TITLE" \
  --generate-notes \
  --latest

RELEASE_URL="$(gh release view "$TAG" -R "$REPO" --json url --jq '.url')"

step "Update AltStore source"

RELEASE_DATE="$(date +%Y-%m-%d)"

python3 - \
  "$SOURCE_JSON" \
  "$EXPECTED_BUNDLE_ID" \
  "$VERSION" \
  "$BUILD" \
  "$RELEASE_DATE" \
  "$VERSION_NOTES" \
  "$DOWNLOAD_URL" \
  "$IPA_SIZE_BYTES" \
  "$MIN_OS_VERSION" \
  "$IPA_SHA" <<'PY'
import json
import sys

(
    path,
    bundle_id,
    version,
    build,
    release_date,
    notes,
    download_url,
    size_bytes,
    min_os,
    sha256,
) = sys.argv[1:]

with open(path, encoding="utf-8") as f:
    source = json.load(f)

apps = [a for a in source.get("apps", []) if a.get("bundleIdentifier") == bundle_id]
if len(apps) != 1:
    raise SystemExit(f"Expected exactly one app with bundleIdentifier {bundle_id}, found {len(apps)}")

app = apps[0]
versions = app.setdefault("versions", [])
versions[:] = [
    item for item in versions
    if not (
        str(item.get("version")) == version
        and str(item.get("buildVersion")) == build
    )
]

new_version = {
    "version": version,
    "buildVersion": build,
    "date": release_date,
    "localizedDescription": notes,
    "downloadURL": download_url,
    "size": int(size_bytes),
    "minOSVersion": min_os,
    "sha256": sha256,
}
versions.insert(0, new_version)

with open(path, "w", encoding="utf-8") as f:
    json.dump(source, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY

python3 -m json.tool "$SOURCE_JSON" >/dev/null || fail "Updated AltStore source is invalid JSON."
git diff --check -- "$SOURCE_RELATIVE_PATH" || fail "AltStore source contains whitespace errors."

if git diff --quiet -- "$SOURCE_RELATIVE_PATH"; then
  fail "AltStore source did not change after publishing $VERSION ($BUILD)."
fi

python3 - "$SOURCE_JSON" "$EXPECTED_BUNDLE_ID" "$VERSION" "$BUILD" "$DOWNLOAD_URL" <<'PY'
import json
import sys

path, bundle_id, version, build, download_url = sys.argv[1:]
with open(path, encoding="utf-8") as f:
    source = json.load(f)
app = next(a for a in source["apps"] if a.get("bundleIdentifier") == bundle_id)
latest = app["versions"][0]
assert str(latest["version"]) == version
assert str(latest["buildVersion"]) == build
assert latest["downloadURL"] == download_url
PY

git add "$SOURCE_RELATIVE_PATH"
git commit -m "Update AltStore source to ${VERSION} (${BUILD})"
git push "$REMOTE" "HEAD:refs/heads/$BRANCH"

SOURCE_COMMIT="$(git rev-parse HEAD)"

step "Release complete"

echo "Release:       $RELEASE_URL"
echo "IPA:           $IPA_PATH"
echo "Download:      $DOWNLOAD_URL"
echo "SHA-256:       $IPA_SHA"
echo "Build log:     $LOG_PATH"
echo "AltStore:      $SOURCE_URL"
echo "Source commit: ${SOURCE_COMMIT:0:12}"

if [[ "$IS_PRIVATE" == "true" ]]; then
  echo
  echo "WARNING: This repository is private."
  echo "AltStore cannot fetch the raw source or IPA without GitHub authentication."
fi

if [[ "$NO_OPEN" -ne 1 ]]; then
  open "$RELEASE_URL" >/dev/null 2>&1 || true
  open -R "$IPA_PATH" >/dev/null 2>&1 || true
fi
