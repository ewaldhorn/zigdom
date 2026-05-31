# Zigdom

A [Zig](https://ziglang.org/) WASM DOM manipulation library.

This demonstrates Zig compiled to `wasm32-freestanding` targeting the browser,
with a minimal JS glue layer.

## Why

Building browser-based dashboards and interactive pages in a systems language is 
satisfying. Zig gives us tight WASM output, compile-time asset embedding (`@embedFile`), 
and zero hidden runtime overhead.

## Structure

```
src/
  dom.zig      Core DOM library — 22 API functions
  demo.zig     Demo application with embedded assets and event callbacks
docs/
  index.html   Page you open in the browser
  styles.css   Page styles 
  zigdom.js    JS glue — handle table, string bridge, callback dispatch
  zigdom.wasm  Built binary (gitignored)
  bodystyle.css  Embedded by demo.zig at compile time
  dommie.txt     Embedded text displayed in the demo
```

## Build & Run

```bash
./build.sh          # zig build-exe → docs/zigdom.wasm
./run.sh            # build + http-server on :9000
```

Or serve `docs/` with any static server after building.

## How It Works

Zigdom uses a lightweight JS bridge:

- **Handle table** — JS stores references to live DOM elements in an array.
  Zig passes integer handles instead of raw pointers.
- **String bridge** — Strings are passed as `(ptr, len)` pairs into WASM
  linear memory. The JS side reads/writes via `TextDecoder`/`TextEncoder`.
- **Callback table** — Zig exports `zig_invoke_callback(u32)`. JS event
  listeners call it by ID when DOM events fire.
- **No GC** — No hidden allocations, no finalizers. What Zig allocates,
  Zig frees (or the page unloads).

## API 

| Concern | Functions |
|---|---|
| Element creation | `createElement`, `createDiv`, `createParagraph(WithText)`, `createButton`, `createImg` |
| Element access | `getElementById`, `getString`, `setValue`, `setFocus` |
| Element manipulation | `addElementTo`, `removeAllChildElementsFrom`, `wrapElementWithNewDiv` |
| Style | `addNewStyleElement`, `addClass`, `removeClass`, `replaceClasses` |
| Visibility | `hide`, `show` |
| Events | `addEventListener`, `addEventListenerById` |
| Utilities | `log`, `showAlert` |
