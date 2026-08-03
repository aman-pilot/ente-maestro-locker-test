#!/usr/bin/env bash

set -euo pipefail

app_id="io.ente.locker.independent"
readonly workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly selector="$workspace_root/scripts/select-locker-ci-suites.sh"

usage() {
    cat <<'EOF'
Usage: scripts/run-locker-android-local.sh --apk <path> [options]

Run one account-free Locker Android Maestro suite against an explicitly
selected local device.

Options:
  --apk <path>       Locker APK to install before the run (required).
  --maestro <path>   Maestro executable. Defaults to MAESTRO_BIN or maestro.
  --app-id <id>      Application ID. Defaults to io.ente.locker.independent.
  --serial <serial>  adb serial. Defaults to ANDROID_SERIAL or the only device.
  --suite <name>     onboarding or all. Defaults to all.
  --skip-install     Reuse the installed Locker app.
  -h, --help         Show this help.
EOF
}

apk_path=""
maestro_bin="${MAESTRO_BIN:-maestro}"
serial="${ANDROID_SERIAL:-}"
suite="all"
install_apk=true
output_dir="${LOCKER_MAESTRO_OUTPUT_DIR:-artifacts/maestro/local}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apk)
            apk_path="${2:?--apk requires a path}"
            shift 2
            ;;
        --maestro)
            maestro_bin="${2:?--maestro requires a path}"
            shift 2
            ;;
        --app-id)
            app_id="${2:?--app-id requires an application id}"
            shift 2
            ;;
        --serial)
            serial="${2:?--serial requires a device serial}"
            shift 2
            ;;
        --suite)
            suite="${2:?--suite requires a suite name}"
            shift 2
            ;;
        --skip-install)
            install_apk=false
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$apk_path" ]]; then
    echo "--apk is required" >&2
    usage >&2
    exit 2
fi

if [[ ! -f "$apk_path" ]]; then
    echo "APK not found: $apk_path" >&2
    exit 2
fi

if ! "$maestro_bin" --version > /dev/null; then
    echo "Maestro executable is not runnable: $maestro_bin" >&2
    exit 2
fi

if [[ -z "$serial" ]]; then
    devices=()
    while IFS= read -r device; do
        devices+=("$device")
    done < <(adb devices | awk 'NR > 1 && $2 == "device" { print $1 }')
    if [[ ${#devices[@]} -ne 1 ]]; then
        echo "Set --serial or ANDROID_SERIAL when zero or multiple devices are attached" >&2
        exit 2
    fi
    serial=${devices[0]}
fi

if [[ "$(adb -s "$serial" get-state)" != "device" ]]; then
    echo "adb device is not ready: $serial" >&2
    exit 2
fi

case "$suite" in
    all)
        matrix=$($selector --all)
        ;;
    onboarding)
        matrix=$($selector --suite "$suite")
        ;;
    *)
        echo "Unknown suite: $suite" >&2
        usage >&2
        exit 2
        ;;
esac

flows=()
while IFS= read -r flow; do
    [[ -n "$flow" ]] && flows+=("$flow")
done < <(jq -r '.include[].flows' <<< "$matrix" | tr ' ' '\n')
if [[ ${#flows[@]} -eq 0 ]]; then
    echo "Suite selected no flows: $suite" >&2
    exit 2
fi

cd "$workspace_root"
mkdir -p "$output_dir"

if [[ "$install_apk" == true ]]; then
    adb -s "$serial" uninstall "$app_id" > /dev/null 2>&1 || true
    adb -s "$serial" install -r "$apk_path"
fi

adb -s "$serial" shell settings put system screen_off_timeout 2147483647
"$maestro_bin" test \
    --no-ansi \
    --udid "$serial" \
    -e "APP_ID=$app_id" \
    --format JUNIT \
    --output "$output_dir/${suite}-results.xml" \
    --debug-output "$output_dir/${suite}-debug" \
    --flatten-debug-output \
    "${flows[@]}"
