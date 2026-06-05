#!/bin/bash
# build.sh — Build the Zigdom WASM module via the Zig build system
# Requires Zig 0.16.0+. Output goes to docs/zigdom.wasm.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Building zigdom.wasm (demo) ..."
cd demo
zig build
cd "$SCRIPT_DIR"

WASM_OUT="docs/zigdom.wasm"
echo "==> Done. WASM binary: $(wc -c < "${WASM_OUT}") bytes"
