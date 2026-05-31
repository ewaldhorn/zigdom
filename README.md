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

## Using in Your Project

Zigdom is designed to be vendored — copy `src/dom.zig` into your project
and point your WASM build at it. No package manager step needed.

### 1. Add the library

Copy `dom.zig` into your project:

```bash
curl -O https://raw.githubusercontent.com/ewaldhorn/zigdom/main/src/dom.zig
```

Or as a git submodule:

```bash
git submodule add https://github.com/ewaldhorn/zigdom lib/zigdom
```

### 2. Zig code

Import `dom.zig`, call `init()`, then use the API:

```zig
const dom = @import("dom.zig");

export fn zig_init() void {
    dom.init();

    const h1 = dom.createElement("h1");
    h1.setInnerText("Hello from Zig!");
    dom.addToBody(h1);
}
```

If your app uses DOM event callbacks, also export `zig_invoke_callback`:

```zig
export fn zig_invoke_callback(id: u32) void {
    switch (id) {
        0 => myClickHandler(),
        else => {},
    }
}
```

### 3. JS glue

`dom.zig` depends on `zigdom.js` at runtime — it provides the handle table,
string bridge, and callback dispatch. Include it in your HTML before your
WASM load code:

```html
<script src="zigdom.js"></script>
```

Copy it from this repo:

```bash
curl -O https://raw.githubusercontent.com/ewaldhorn/zigdom/main/docs/zigdom.js
```

### 4. Build

Compile to WASM with the required flags:

```bash
zig build-exe src/main.zig \
    -target wasm32-freestanding \
    -fno-entry \
    -rdynamic \
    -O ReleaseSmall \
    --export=zig_init \
    --export=zig_invoke_callback \
    -femit-bin=docs/app.wasm
```

`-fno-entry` skips the C runtime, `-rdynamic` exports all symbols so JS can
call `zig_init`, and `--export` keeps the entry-point and callback-dispatch
symbols alive for the linker.

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
