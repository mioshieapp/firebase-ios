#!/bin/bash

set -e

ROOT_DIR="$(pwd)"
REPO="firebase/firebase-ios-sdk"
MY_REPO="mioshieapp/firebase-ios"
VERSION=""
TAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [ -n "$2" ] || { echo "--version requires a value"; exit 1; }
      VERSION="$2"
      shift 2
      ;;
    --tag)
      [ -n "$2" ] || { echo "--tag requires a value"; exit 1; }
      TAG="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: ./update.sh [--version VERSION] [--tag TAG]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [ -z "$VERSION" ]; then
  VERSION=$(gh release list --repo $REPO --exclude-pre-releases --limit 1 --json tagName -q '.[0].tagName')
fi

if [ -z "$TAG" ]; then
  TAG="$VERSION"
fi

if git rev-parse "refs/tags/${TAG}" >/dev/null 2>&1; then
  echo "Tag ${TAG} already exists. No update needed."
  exit 0
fi

OUTPUT_DIR="$(pwd)/.output"
FB_DIR="$OUTPUT_DIR/Firebase"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "Firebase Version: $VERSION"
echo "Release Tag: $TAG"

curl -LO "https://github.com/$REPO/releases/download/$VERSION/Firebase.zip"
unzip -qo Firebase.zip -d "$OUTPUT_DIR"
rm Firebase.zip

BINARY_TARGETS=""
ZIPS=()

package() {
  local name=$1
  local zip_path="$OUTPUT_DIR/$name.zip"
  echo "Packaging $name..."

  find "$name" -name "*.xcframework" -type d | while read -r xc; do
    find "$xc" -maxdepth 1 -mindepth 1 -type d ! -name "*ios*" -exec rm -rf {} +
  done

  (cd "$name" && zip -r "$zip_path" .)

  local sum
  sum=$(sha256sum "$zip_path")
  sum=${sum%% *}

  [ -n "$BINARY_TARGETS" ] && BINARY_TARGETS+=",\\n\\n"
  BINARY_TARGETS+=".binaryTarget(
    name: \"$name\",
    url: \"https://github.com/$MY_REPO/releases/download/$TAG/$name.zip\",
    checksum: \"$sum\"
)"
  ZIPS+=("$zip_path")
}

cd "$FB_DIR"

cp "module.modulemap" "FirebaseAnalytics/"
cp "Firebase.h" "FirebaseAnalytics/"


package "FirebaseAnalytics"
package "FirebaseRemoteConfig"
package "FirebaseAppCheck"
package "FirebaseAuth"
package "FirebaseFirestore"
package "GoogleSignIn"
package "FirebaseFunctions"
package "FirebaseCrashlytics"

cd "$ROOT_DIR"

RELEASE_NOTES="SPM binaryTargets

\`\`\`swift
$BINARY_TARGETS
\`\`\`"

BUILD=$(date +%s)
echo "$VERSION.$BUILD" >version

git add version
git commit -m "v$TAG"

git tag -a "$TAG" -m "v$TAG"
git push origin HEAD --tags

echo "Creating release $TAG..."
gh release create "$TAG" "${ZIPS[@]}" --notes "$(echo -e "$RELEASE_NOTES")"

echo "Done."
