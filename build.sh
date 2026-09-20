#!/usr/bin/env bash
#
# Build (and flash) the swifty firmware.
#
#   ./build.sh              # build both halves; flash each if its bootloader volume is mounted
#   ./build.sh left         # build + flash the left half
#   ./build.sh right        # build + flash the right half
#   ./build.sh --no-flash   # build only
#   ./build.sh left --no-flash
#
#   ./build.sh reset        # build the settings-reset firmware. Flash it to BOTH
#                           #   halves to clear the stored BLE bonds (including the
#                           #   central<->peripheral pairing), then reflash the
#                           #   normal left/right images.
#
# The copy to the bootloader volume is skipped, with a warning, when the volume is
# not mounted, so this still builds with no half plugged in. Override the mount
# point with:  MOUNT=/run/media/beliasson/SWIPPY ./build.sh left
#
# Only one half should be in bootloader mode at a time - both halves present
# themselves as a volume named SWIPPY, so a second one shows up as SWIPPY1.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# Must be fully qualified: there is also a legacy `boards/arm/swippy` board that
# bare `-b swippy` resolves to, and it lacks the /EXT_POWER node the swifty shield
# overrides. The qualifiers come from config/boards/beliasson/swippy/board.yml.
BOARD="${BOARD:-swippy/nrf52840/zmk}"
MOUNT="${MOUNT:-/media/beliasson/SWIPPY}"

# The `west` on PATH can be missing its python deps; prefer the workspace venv.
if [[ -x "$ROOT/.venv/bin/west" ]]; then
    export PATH="$ROOT/.venv/bin:$PATH"
fi

if ! west --version >/dev/null 2>&1; then
    echo "error: no working 'west' - activate your Zephyr/venv environment first" >&2
    exit 1
fi

# Zephyr SDK. The nRF Connect extension's managed copy (~/.zephyr_ide) is not
# present on every machine, so fall back to a locally installed SDK.
export ZEPHYR_TOOLCHAIN_VARIANT="${ZEPHYR_TOOLCHAIN_VARIANT:-zephyr}"
if [[ -z "${ZEPHYR_SDK_INSTALL_DIR:-}" ]]; then
    for d in "$HOME"/.local/opt/zephyr-sdk-* "$HOME"/zephyr-sdk-*; do
        if [[ -d "$d" ]]; then
            export ZEPHYR_SDK_INSTALL_DIR="$d"
            break
        fi
    done
fi
if [[ -z "${ZEPHYR_SDK_INSTALL_DIR:-}" ]]; then
    echo "error: no Zephyr SDK found - set ZEPHYR_SDK_INSTALL_DIR" >&2
    exit 1
fi
echo "SDK: $ZEPHYR_SDK_INSTALL_DIR"

# Local ZMK patches. zmk.patch is applied to the zmk checkout on every build
# because `west update` resets it. --reverse --check detects the already-applied
# state, so this is idempotent and a stale patch fails loudly instead of
# silently building unpatched firmware.
patch_zmk() {
    local patch="$ROOT/zmk.patch"
    [[ -f "$patch" ]] || return 0
    if git -C "$ROOT/zmk" apply --reverse --check "$patch" >/dev/null 2>&1; then
        echo "zmk.patch: already applied"
    elif git -C "$ROOT/zmk" apply --check "$patch" >/dev/null 2>&1; then
        echo "zmk.patch: applying"
        git -C "$ROOT/zmk" apply "$patch"
    else
        echo "error: zmk.patch does not apply to the zmk checkout" >&2
        echo "       check 'git -C zmk status', then refresh the patch" >&2
        exit 1
    fi
}

build() { # $1 = left | right | reset
    local shield
    if [[ $1 == reset ]]; then
        # ZMK's stock settings-reset shield: wipes stored settings (BLE bonds,
        # output, RGB state) on boot, with Bluetooth off so the halves do not
        # re-pair until both have been reset.
        shield="settings_reset"
    elif [[ $1 == right ]]; then
        # The right half is the central and carries the touchpad add-on, so its
        # shield list must include tps65_swifty or pointing silently disappears.
        shield="swifty_right tps65_swifty"
    else
        shield="swifty_$1"
    fi

    echo "==> building $shield"
    west build -p -d "build/$1" zmk/app -b "$BOARD" -- \
        -DZMK_CONFIG="$ROOT/config" -DSHIELD="$shield"
}

flash() { # $1 = left | right
    local uf2="build/$1/zephyr/zmk.uf2"

    if [[ ! -d "$MOUNT" ]]; then
        echo "!! $MOUNT not mounted - skipping flash of the $1 half"
        echo "   put that half in bootloader mode, then: $0 $1 --no-build"
        return
    fi

    echo "==> flashing $1 half -> $MOUNT"
    # An error here is normal: the bootloader ejects the volume once it has the file.
    cp "$uf2" "$MOUNT/" || echo "!! copy reported an error (expected if the volume already ejected)"
}

sides=()
do_flash=1
do_build=1
for arg in "$@"; do
    case "$arg" in
        left | right | reset) sides+=("$arg") ;;
        --no-flash) do_flash=0 ;;
        --no-build) do_build=0 ;;
        -h | --help)
            echo "usage: $0 [left|right|reset] [--no-flash] [--no-build]"
            exit 0
            ;;
        *)
            echo "usage: $0 [left|right|reset] [--no-flash] [--no-build]" >&2
            exit 2
            ;;
    esac
done
[[ ${#sides[@]} -gt 0 ]] || sides=(left right)

if [[ $do_build -eq 1 ]]; then
    patch_zmk
fi

for side in "${sides[@]}"; do
    if [[ $do_build -eq 1 ]]; then
        build "$side"
    fi
    if [[ $do_flash -eq 1 ]]; then
        flash "$side"
    fi
done
