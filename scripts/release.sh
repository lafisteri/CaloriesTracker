#!/bin/zsh

set -euo pipefail

# ------------------------------------------------------------
# CaloriesTracker release configuration
# ------------------------------------------------------------

APP_NAME="CaloriesTracker"
SCHEME="CaloriesTracker"
CONFIGURATION="Release"
REMOTE="origin"

ROOT="$(git rev-parse --show-toplevel)"
OUTPUT_DIR="$HOME/Desktop/CaloriesTrackerIPA"
ARCHIVES_ROOT="$HOME/Library/Developer/Xcode/Archives"

cd "$ROOT"

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

fail() {
    echo
    echo "❌ $1"
    exit 1
}

step() {
    echo
    echo "────────────────────────────────────────"
    echo "$1"
    echo "────────────────────────────────────────"
}

# ------------------------------------------------------------
# Requirements
# ------------------------------------------------------------

step "🔎 Проверяю окружение"

command -v git >/dev/null || fail "git не найден"
command -v xcodebuild >/dev/null || fail "xcodebuild не найден"
command -v gh >/dev/null || fail "GitHub CLI (gh) не найден"
command -v zip >/dev/null || fail "zip не найден"

/usr/bin/gh auth status >/dev/null 2>&1 ||
    fail "GitHub CLI не авторизован. Выполни: gh auth login"

git remote get-url "$REMOTE" >/dev/null 2>&1 ||
    fail "Git remote '$REMOTE' не найден"

# ------------------------------------------------------------
# Git safety
# ------------------------------------------------------------

step "🌿 Проверяю Git"

if [[ -n "$(git status --porcelain)" ]]; then
    echo
    git status --short
    echo
    fail "Есть незакоммиченные изменения. Перед релизом сделай commit."
fi

BRANCH="$(git symbolic-ref --quiet --short HEAD || true)"

if [[ -z "$BRANCH" ]]; then
    fail "Git находится в detached HEAD."
fi

COMMIT="$(git rev-parse HEAD)"

echo "Branch: $BRANCH"
echo "Commit: ${COMMIT:0:8}"

# ------------------------------------------------------------
# Find Xcode project
# ------------------------------------------------------------

step "📱 Ищу Xcode project"

PROJECT="$(
    find "$ROOT" \
        -maxdepth 4 \
        -type d \
        -name "CaloriesTrackerIOS.xcodeproj" \
        -print \
        -quit
)"

if [[ -z "$PROJECT" ]]; then
    PROJECT="$(
        find "$ROOT" \
            -maxdepth 4 \
            -type d \
            -name "*.xcodeproj" \
            -print \
            -quit
    )"
fi

[[ -n "$PROJECT" ]] ||
    fail "Не найден .xcodeproj"

echo "Project: $PROJECT"
echo "Scheme:  $SCHEME"

# ------------------------------------------------------------
# Archive
# ------------------------------------------------------------

step "🏗 Собираю iOS Archive"

TODAY="$(date '+%Y-%m-%d')"
TIMESTAMP="$(date '+%Y-%m-%d %H.%M.%S')"

ARCHIVE_DIR="$ARCHIVES_ROOT/$TODAY"
ARCHIVE_PATH="$ARCHIVE_DIR/$APP_NAME $TIMESTAMP.xcarchive"

mkdir -p "$ARCHIVE_DIR"

XCODE_ARGS=(
    -project "$PROJECT"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -destination "generic/platform=iOS"
    -archivePath "$ARCHIVE_PATH"
    -allowProvisioningUpdates
    archive
)

if command -v xcbeautify >/dev/null 2>&1; then
    set -o pipefail
    xcodebuild "${XCODE_ARGS[@]}" | xcbeautify
else
    xcodebuild "${XCODE_ARGS[@]}"
fi

[[ -d "$ARCHIVE_PATH" ]] ||
    fail "Archive не был создан"

echo
echo "✅ Archive:"
echo "$ARCHIVE_PATH"

# ------------------------------------------------------------
# Locate .app
# ------------------------------------------------------------

APP="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"

[[ -d "$APP" ]] ||
    fail "Не найден $APP_NAME.app внутри xcarchive"

INFO_PLIST="$APP/Info.plist"

[[ -f "$INFO_PLIST" ]] ||
    fail "Info.plist не найден"

# ------------------------------------------------------------
# Version
# ------------------------------------------------------------

step "🏷 Читаю версию"

VERSION="$(
    /usr/libexec/PlistBuddy \
        -c "Print :CFBundleShortVersionString" \
        "$INFO_PLIST"
)"

BUILD="$(
    /usr/libexec/PlistBuddy \
        -c "Print :CFBundleVersion" \
        "$INFO_PLIST"
)"

RELEASE_VERSION="${VERSION}.${BUILD}"
TAG="v${RELEASE_VERSION}"

IPA_NAME="${APP_NAME}-${RELEASE_VERSION}.ipa"
IPA_PATH="$OUTPUT_DIR/$IPA_NAME"

echo "Version: $VERSION"
echo "Build:   $BUILD"
echo "Tag:     $TAG"
echo "IPA:     $IPA_NAME"

# ------------------------------------------------------------
# Duplicate release protection
# ------------------------------------------------------------

if gh release view "$TAG" >/dev/null 2>&1; then
    fail "GitHub Release $TAG уже существует. Увеличь Build в Xcode."
fi

# ------------------------------------------------------------
# Create IPA
# ------------------------------------------------------------

step "📦 Создаю IPA"

mkdir -p "$OUTPUT_DIR"

TMP_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT

mkdir -p "$TMP_DIR/Payload"

ditto \
    "$APP" \
    "$TMP_DIR/Payload/$APP_NAME.app"

rm -f "$IPA_PATH"

(
    cd "$TMP_DIR"
    zip -qry "$IPA_PATH" Payload
)

[[ -f "$IPA_PATH" ]] ||
    fail "IPA не создан"

# Basic ZIP integrity check
unzip -tq "$IPA_PATH" >/dev/null ||
    fail "Созданный IPA повреждён"

IPA_SIZE="$(du -h "$IPA_PATH" | awk '{print $1}')"

echo
echo "✅ IPA готов"
echo "$IPA_PATH"
echo "Size: $IPA_SIZE"

# ------------------------------------------------------------
# Push current source
# ------------------------------------------------------------

step "☁️ Отправляю код в GitHub"

echo "git push $REMOTE $BRANCH"

git push "$REMOTE" "$BRANCH"

# ------------------------------------------------------------
# GitHub Release
# ------------------------------------------------------------

step "🚀 Создаю GitHub Release $TAG"

gh release create "$TAG" \
    "$IPA_PATH" \
    --target "$COMMIT" \
    --title "$APP_NAME $VERSION ($BUILD)" \
    --generate-notes \
    --latest

# gh creates the tag remotely. Fetch it locally as well.
git fetch --tags "$REMOTE"

# ------------------------------------------------------------
# Result
# ------------------------------------------------------------

RELEASE_URL="$(
    gh release view "$TAG" \
        --json url \
        --jq '.url'
)"

REPO="$(
    gh repo view \
        --json nameWithOwner \
        --jq '.nameWithOwner'
)"

DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/$IPA_NAME"

step "🎉 RELEASE ГОТОВ"

echo "App:       $APP_NAME"
echo "Version:   $VERSION"
echo "Build:     $BUILD"
echo "Tag:       $TAG"
echo
echo "IPA:"
echo "$IPA_PATH"
echo
echo "GitHub Release:"
echo "$RELEASE_URL"
echo
echo "IPA URL:"
echo "$DOWNLOAD_URL"
echo

open "$RELEASE_URL"
open -R "$IPA_PATH"
