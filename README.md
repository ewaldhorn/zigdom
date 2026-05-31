# Zigdom

A [Zig](https://ziglang.org/) WASM DOM manipulation library.

> [!IMPORTANT]
> This library is fully compatible with and tested on **Zig 0.16.0**.

This demonstrates Zig compiled to `wasm32-freestanding` targeting the browser,
with a minimal JS glue layer.

## Why

Building browser-based dashboards and interactive pages in a systems language is
satisfying. Zig gives us tight WASM output, compile-time asset embedding (`@embedFile`),
and zero hidden runtime overhead.

## Structure

```
src/
  dom.zig        Core DOM library — low-level JS DOM and Canvas 2D bindings
  canvas.zig     In-memory pixel canvas, Bresenham lines, circles, and shapes
  colour.zig     RGBA colour structures, grayscale conversions, and PRNG
  demo.zig       Demo entry point (DOM controls + two real-time graphics canvases)
  bodystyle.css  CSS embedded into the WASM binary at compile time (@embedFile)
  zigdom.txt     Text embedded into the WASM binary at compile time (@embedFile)
docs/
  index.html   Page you open in the browser
  styles.css   Page styles
  zigdom.js    JS glue — handle table, string bridge, direct-memory canvas rendering
  zigdom.wasm  Built binary (see .gitignore)
```

## Build & Run

Ensure you have **Zig 0.16.0** installed, then run:

```bash
./build.sh          # zig build-exe → docs/zigdom.wasm
./run.sh            # build + http-server on :9000
```

Or serve `docs/` with any static server after building.

## How It Works

Zigdom uses a lightweight JS bridge:

- **Handle table** — JS stores references to live DOM elements in an array.
  Zig passes integer handles (`u32`) instead of raw pointers.
- **String bridge** — Strings are passed as `(ptr, len)` pairs into WASM
  linear memory. JS reads/writes via `TextDecoder`/`TextEncoder`.
- **Callback table** — Zig exports `zig_invoke_callback(u32)`. JS event
  listeners and `requestAnimationFrame` call it by ID when events fire.
- **Zero-copy canvas** — The pixel buffer lives inside WASM memory. JS
  creates a `Uint8ClampedArray` view directly on it and calls `putImageData`
  — no copy between Zig and the browser canvas.
- **No GC** — No hidden allocations, no finalizers. All data lives in
  fixed-size global arrays in the WASM data segment.

## Using in Your Project

Zigdom is designed to be vendored — copy `src/dom.zig` (and optionally
`src/canvas.zig` / `src/colour.zig`) into your project and point your WASM
build at them. No package manager step needed.

### 1. Add the library

Copy `dom.zig` into your project:

```bash
curl -O https://raw.githubusercontent.com/ewaldhorn/zigdom/main/src/dom.zig
```

If you also want the in-memory pixel canvas primitives:

```bash
curl -O https://raw.githubusercontent.com/ewaldhorn/zigdom/main/src/canvas.zig
curl -O https://raw.githubusercontent.com/ewaldhorn/zigdom/main/src/colour.zig
```

Or as a git submodule:

```bash
git submodule add https://github.com/ewaldhorn/zigdom lib/zigdom
```

### 2. Zig code

Import `dom.zig`, call `dom.init()` once at startup, then use the API:

```zig
const dom = @import("dom.zig");

export fn zig_init() void {
    dom.init();  // must be called first — captures document/body/head handles

    const h1 = dom.createElement("h1");
    dom.setInnerText(h1, "Hello from Zig!");
    dom.addToBody(h1);
}
```

If your app responds to DOM events or drives an animation loop, also export
`zig_invoke_callback`. JS will call it with the numeric ID you registered:

```zig
export fn zig_invoke_callback(id: u32) void {
    switch (id) {
        0 => myButtonHandler(),
        1 => myAnimationTick(),
        else => {},
    }
}
```

If you use the `zig_set_interaction` touch/click bridge (for passing canvas
coordinates to Zig), export that function too:

```zig
export fn zig_set_interaction(x: i32, y: i32) void {
    // store x, y for the next callback invocation
}
```

> [!WARNING]
> `getString` and `get` return slices that point into a shared 4 KB scratch
> buffer. **Do not hold a reference across a second call** to any
> string-retrieval function — copy the slice if you need it to persist.

### 3. JS glue

`dom.zig` depends on `zigdom.js` at runtime — it provides the handle table,
string bridge, and event/animation dispatch. Include it in your HTML and load
the WASM binary using the `ZigDom.instantiate` helper:

```html
<script src="zigdom.js"></script>
<script type="module">
  ZigDom.instantiate("app.wasm").catch(err => {
    console.error("Zigdom failed to load:", err);
  });
</script>
```

Copy `zigdom.js` from this repo:

```bash
curl -O https://raw.githubusercontent.com/ewaldhorn/zigdom/main/docs/zigdom.js
```

### 4. Build

Compile to WASM with the required flags. Export every function that JS needs
to call directly:

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

If you use `zig_set_interaction`, add it to the export list:

```bash
    --export=zig_set_interaction \
```

**Flag notes:**
- `-fno-entry` — skips the C runtime entry point (no `main`).
- `-rdynamic` — exports all symbols so JS can call `zig_init` and friends.
- `--export=<fn>` — keeps each exported symbol alive through the linker dead-code pass.
- `-O ReleaseSmall` — optimises for binary size; `ReleaseFast` is also valid.

## API

### `dom.zig` — Core DOM

| Concern | Functions |
|---|---|
| Initialisation | `init()` |
| Element creation | `createElement`, `createDiv`, `createParagraph`, `createParagraphWithText`, `createButton`, `createImg` |
| Element access | `getElementById`, `getString`, `setValue`, `setFocus` |
| Element manipulation | `addElementTo`, `addToBody`, `removeAllChildElementsFrom`, `wrapElementWithNewDiv` |
| Inner content | `setInnerText`, `setInnerHTML` |
| Property access (by handle) | `set`, `get` |
| Style (by element ID) | `addNewStyleElement`, `addClass`, `removeClass` |
| Style (by handle) | `addClassTo`, `removeClassFrom`, `replaceClasses` |
| Visibility | `hide`, `show` |
| Events | `addEventListener`, `addEventListenerById` |
| Animation | `startAnimationLoop` |
| Utilities | `log`, `showAlert` |

### `canvas.zig` — In-Memory Pixel Canvas

All drawing goes into a WASM-side byte buffer; call `Canvas.render()` to blit
it to the browser canvas in one zero-copy operation.

| Concern | Functions |
|---|---|
| Lifecycle | `Canvas.init`, `Canvas.render` |
| Fill | `Canvas.clearScreen` |
| Colour state | `Canvas.setColour`, `Canvas.getColour` |
| Pixels | `Canvas.putPixel`, `Canvas.colourPutPixel`, `Canvas.getPixel` |
| Lines | `Canvas.line`, `Canvas.colourLine`, `Canvas.linePoint`, `Canvas.colourLinePoint` |
| Circles | `Canvas.circle`, `Canvas.colourCircle`, `Canvas.filledCircle`, `Canvas.colourFilledCircle`, `Canvas.borderCircle`, `Canvas.colourBorderCircle` |
| Rectangles | `Canvas.filledRectangle`, `Canvas.colourFilledRectangle`, `Canvas.rectangle`, `Canvas.colourRectangle` |
| Triangles | `Canvas.triangle` |
| 2D context | `Canvas.getContext2D` → `Context2D.beginPath`, `.fill`, `.arc`, `.fillStyle` |

### `colour.zig` — Colour Primitives

| Concern | Functions / Types |
|---|---|
| Type | `Colour` — `{ r, g, b, a: u8 }` |
| Constants | `Colour.white`, `Colour.black`, `Colour.empty` |
| Queries | `Colour.isEmpty` |
| Conversions | `Colour.convertToGrayscale` |
| PRNG | `randomColour()`, `seed(u64)` |

> [!NOTE]
> `Point` (`{ x, y: i32 }`) is defined in `canvas.zig`, not `colour.zig`.

> [!NOTE]
> `randomColour()` and `Colour.convertToGrayscale` use an internal
> xorshift64 PRNG seeded at 1337. Call `colour.seed(n)` with a non-zero
> value to get a different random sequence.
