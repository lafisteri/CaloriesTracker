#!/bin/bash
set -euo pipefail

# CaloriesTracker: archive -> IPA -> GitHub Release
# Assumes the Xcode project was flattened into the repository root.

APP_NAME="CaloriesTracker"
SCHEME="CaloriesTracker"
CONFIGURATION="Release"
EXPECTED_BUNDLE_ID="com.caloriestracker.ios"
REMOTE="origin"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" ]]; then
  echo "ERROR: Run this script from inside the CaloriesTracker Git repository."
  exit 1
fi

PROJECT="$ROOT/CaloriesTracker.xcodeproj"
ARTIFACTS_DIR="$ROOT/artifacts"
IPA_DIR="$ARTIFACTS_DIR/ipa"
LOG_DIR="$ARTIFACTS_DIR/logs"
WORK_DIR="$ARTIFACTS_DIR/.release-work"
DERIVED_DATA="$WORK_DIR/DerivedData"
ARCHIVE_PATH="$WORK_DIR/$APP_NAME.xcarchive"
PACKAGE_DIR="$WORK_DIR/package"

ASSUME_YES=0
NO_OPEN=0

usage() {
  cat <<USAGE
Usage: ./scripts/release.sh [options]

Options:
  -y, --yes       Skip the final confirmation prompt
      --no-open   Do not open Finder/GitHub after completion
  -h, --help      Show this help
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

for tool in git xcodebuild gh zip unzip shasum codesign ditto; do
  command -v "$tool" >/dev/null 2>&1 || fail "Required command not found: $tool"
done

[[ -d "$PROJECT" ]] || fail "Xcode project not found: $PROJECT"

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

[[ -n "$VERSION" ]] || fail "MARKETING_VERSION could not be read from Xcode build settings."
[[ -n "$BUILD" ]] || fail "CURRENT_PROJECT_VERSION could not be read from Xcode build settings."
[[ "$BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" ]] || fail "Unexpected bundle identifier: $BUNDLE_ID"

# Keep the IPA filename compatible with the existing manual convention.
RELEASE_ID="${VERSION}.${BUILD}"
IPA_NAME="${APP_NAME}-${RELEASE_ID}.ipa"
SHA_NAME="${IPA_NAME}.sha256"
IPA_PATH="$IPA_DIR/$IPA_NAME"
SHA_PATH="$IPA_DIR/$SHA_NAME"

# Tag names keep marketing version and build number visibly separate.
TAG="v${VERSION}-build.${BUILD}"
TITLE="${APP_NAME} ${VERSION} (${BUILD})"
LOG_PATH="$LOG_DIR/release-${RELEASE_ID}.log"

printf 'Repository:  %s\n' "$REPO"
printf 'Branch:      %s\n' "$BRANCH"
printf 'Commit:      %.12s\n' "$COMMIT"
printf 'Version:     %s\n' "$VERSION"
printf 'Build:       %s\n' "$BUILD"
printf 'Bundle ID:   %s\n' "$BUNDLE_ID"
printf 'Tag:         %s\n' "$TAG"
printf 'IPA:         %s\n' "$IPA_PATH"

# Fetch tags before duplicate checks so a previous failed local run is handled safely.
git fetch --quiet --tags "$REMOTE"

if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
  fail "GitHub Release $TAG already exists. Increase the Xcode build number."
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
  TAG_COMMIT="$(git rev-list -n 1 "$TAG")"
  [[ "$TAG_COMMIT" == "$COMMIT" ]] || fail "Tag $TAG already points to a different commit. Increase the build number."
fi

if [[ "$ASSUME_YES" -ne 1 ]]; then
  echo
  read -r -p "Archive, package, push, and publish this release? [y/N] " ANSWER
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

[[ "$ARCHIVE_VERSION" == "$VERSION" ]] || fail "Archive version does not match preflight version."
[[ "$ARCHIVE_BUILD" == "$BUILD" ]] || fail "Archive build does not match preflight build."
[[ "$ARCHIVE_BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" ]] || fail "Archive bundle identifier changed unexpectedly."

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

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

IPA_SIZE="$(du -h "$IPA_PATH" | awk '{ print $1 }')"
IPA_SHA="$(awk '{ print $1 }' "$SHA_PATH")"

echo "IPA created: $IPA_PATH"
echo "Size:        $IPA_SIZE"
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
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/$IPA_NAME"

step "Release complete"

echo "Release:     $RELEASE_URL"
echo "IPA:         $IPA_PATH"
echo "Download:    $DOWNLOAD_URL"
echo "SHA-256:     $IPA_SHA"
echo "Build log:   $LOG_PATH"

if [[ "$IS_PRIVATE" == "true" ]]; then
  echo
  echo "NOTE: This repository is private. The direct download URL requires GitHub authentication"
  echo "and cannot be used as a public AltStore Source URL without a public release host."
fi

if [[ "$NO_OPEN" -ne 1 ]]; then
  open "$RELEASE_URL" >/dev/null 2>&1 || true
  open -R "$IPA_PATH" >/dev/null 2>&1 || true
fi
