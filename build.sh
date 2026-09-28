#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release --product StudyTimelapse
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/Study Timelapse.app"
# Stage outside a synced directory: File Provider can add FinderInfo to .app folders.
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/study-timelapse.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
staged_app="$staging_dir/Study Timelapse.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$binary_dir/StudyTimelapse" "$staged_app/Contents/MacOS/StudyTimelapse"
cp Resources/Info.plist "$staged_app/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$staged_app/Contents/Resources/"; fi
codesign --force --sign - --identifier local.studytimelapse.mac "$staged_app"
plutil -lint "$staged_app/Contents/Info.plist"
codesign --verify --deep --strict "$staged_app"
ditto --norsrc --noextattr --noqtn -c -k --keepParent "$staged_app" "$PWD/Study Timelapse.zip"
mkdir -p "$staging_dir/verify"
ditto -x -k "$PWD/Study Timelapse.zip" "$staging_dir/verify"
codesign --verify --deep --strict "$staging_dir/verify/Study Timelapse.app"
ditto --norsrc --noextattr --noqtn "$staged_app" "$app_dir"
printf '\nBuilt and verified: %s\n' "$PWD/Study Timelapse.zip"
printf 'Local app: %s\n' "$app_dir"
