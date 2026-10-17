#!/usr/bin/env bash
# Build the lever firmware. The USB product name "Phaethon Levers" is what LeverInput
# matches on (godot/input/lever_input.gd LEVER_NAMES), so unknown HID devices such as
# analog keyboards are never mistaken for the levers.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cli="${LOCALAPPDATA}/Programs/arduino-cli/arduino-cli.exe"
# --clean: a cached core build silently kept the old "Pico" product name (2026-10-17).
"$cli" compile --clean --fqbn rp2040:rp2040:rpipico \
  --build-property 'build.usb_product="Phaethon Levers"' \
  --build-property 'build.usb_manufacturer="Phaethon"' \
  --output-dir "$here/build" "$here/phaethon_levers"
