#!/bin/sh

set -eu

if [ "${PLATFORM_NAME:-}" = "iphonesimulator" ]; then
    exit 0
fi

state_file="$SRCROOT/.swiftify_build_number.local"
lock_directory="$SRCROOT/.swiftify_build_number.lock"
attempt=0

until mkdir "$lock_directory" 2>/dev/null; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 100 ]; then
        echo "Could not acquire the build number lock."
        exit 1
    fi
    sleep 0.1
done

trap 'rmdir "$lock_directory" 2>/dev/null || true' EXIT INT TERM

date_key="$(date +%y%m.%d)"
previous_date=""
previous_sequence="0"

if [ -f "$state_file" ]; then
    read -r previous_date previous_sequence < "$state_file" || true
fi

case "$previous_sequence" in
    ''|*[!0-9]*) previous_sequence="0" ;;
esac

if [ "$previous_date" = "$date_key" ]; then
    sequence=$((previous_sequence + 1))
else
    sequence="1"
fi

if [ "$sequence" -gt 99 ]; then
    echo "The daily build number limit of 99 has been reached."
    exit 1
fi

build_number="$date_key.$sequence"
info_plist="$TARGET_BUILD_DIR/$INFOPLIST_PATH"

if [ ! -f "$info_plist" ]; then
    echo "The generated Info.plist was not found at $info_plist."
    exit 1
fi

if /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$info_plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$info_plist"
else
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $build_number" "$info_plist"
fi

printf '%s %s\n' "$date_key" "$sequence" > "$state_file"
echo "Swiftify build number: $build_number"
