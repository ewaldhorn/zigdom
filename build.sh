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
CACHE_DIR="/tmp/zigdom-cache-$$"

mkdir -p "${CACHE_DIR}"

echo "==> Building ${WASM_OUT} ..."

$ZIG build-exe src/demo.zig \
    --cache-dir "${CACHE_DIR}" \
    -target wasm32-freestanding \
    -fno-entry \
    -rdynamic \
    -O ReleaseSmall \
    --export=zig_init \
    --export=zig_invoke_callback \
    -femit-bin="${WASM_OUT}"

rm -rf "${CACHE_DIR}"

echo "==> Done. WASM binary: $(wc -c < "${WASM_OUT}") bytes"
