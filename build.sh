#!/bin/bash
# build.sh — Compile the Zigdom WASM module
# Uses zig build-exe targeting wasm32-freestanding with -rdynamic
# to export functions and keep symbols for JS-side invocation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

ZIG=${ZIG:-zig}
OUT_DIR="docs"
WASM_OUT="${OUT_DIR}/zigdom.wasm"

echo "==> Building ${WASM_OUT} ..."

$ZIG build-exe src/demo.zig \
    -target wasm32-freestanding \
    -fno-entry \
    -rdynamic \
    -O ReleaseSmall \
    --export=zig_init \
    --export=zig_invoke_callback \
    --export=zig_get_click_buffer \
    --export=zig_get_click_buffer_len \
    -femit-bin="${WASM_OUT}"

echo "==> Done. WASM binary: $(wc -c < "${WASM_OUT}") bytes"
