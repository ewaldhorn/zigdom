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
build.zig           — Library build definition (module graph for zig fetch)
build.zig.zon       — Package manifest
src/
  dom.zig           — Core DOM library — low-level JS DOM and Canvas 2D bindings
  html.zig          — Declarative HTML element builder (chainable, zero-heap)
  canvas.zig        — In-memory pixel canvas, Bresenham lines, circles, and shapes
  colour.zig        — RGBA colour structures, grayscale conversions, and PRNG
  sound.zig         — Zero-heap UI sound effects generator (pre-rendered button click blip)
demo/
  build.zig          — Demo build (depends on parent zigdom library)
  build.zig.zon      — Demo package manifest
  src/
    demo.zig         — Demo entry point (DOM controls, graphics canvases + sound effect export)
    bodystyle.css    — CSS embedded into the WASM binary at compile time (@embedFile)
    zigdom.txt       — Text embedded into the WASM binary at compile time (@embedFile)
docs/
  index.html         — Page you open in the browser
  styles.css         — Page styles
  zigdom.js          — JS glue — handle table, string bridge, direct-memory canvas, and audio control
  synth-worklet.js   — Dedicated AudioWorklet processor for the retro soundtrack synth
  zigdom.wasm        — Built binary (see .gitignore)
```

## Build & Run

Ensure you have **Zig 0.16.0** installed, then run:

```bash
./build.sh          # zig build → docs/zigdom.wasm
./run.sh            # build + http-server on :9000
```

Or serve `docs/` with any static server after building.

## Using in Your Project

### Step 1: Add the dependency

```bash
zig fetch --save git+https://github.com/ewaldhorn/zigdom
```

This adds zigdom to your `build.zig.zon`:

```zig
// in build.zig.zon
.zigdom = .{
    .url = "git+https://github.com/ewaldhorn/zigdom",
    .hash = "...",   // auto-filled by zig fetch
},
```

### Step 2: Wire up your `build.zig`

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const optimize = b.standardOptimizeOption(.{});

    // Fetch the zigdom library modules
    const zigdom_dep = b.dependency("zigdom", .{
        .target = target,
        .optimize = optimize,
    });

    // Create your WASM executable
    const exe = b.addExecutable(.{
        .name = "app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Import only the modules you need
    exe.root_module.addImport("dom", zigdom_dep.module("dom"));
    exe.root_module.addImport("html", zigdom_dep.module("html"));

    // WASM-specific: no main, export all public symbols
    exe.entry = .disabled;
    exe.rdynamic = true;

    b.installArtifact(exe);
}
```

> [!TIP]
> You only need to import the modules your code actually uses — `html`,
> `canvas`, `colour`, and `sound` are optional. Pick what you need.

See [`demo/build.zig`](demo/build.zig) for a complete working example
(including the install-to-`docs/` pattern).

### Step 3: Write your Zig code

Import modules by name — **not** by file path:

```zig
const dom = @import("dom");
const html = @import("html");

export fn zig_init() void {
    dom.init();   // must be called first

    const h1 = dom.createElement("h1");
    dom.setInnerText(h1, "Hello from Zig!");
    dom.addToBody(h1);
}
```

> [!WARNING]
> `getString` and `Handle.get` return slices that point into a shared 4 KB
> scratch buffer. **Copy the slice if you need it to persist** across
> multiple string-retrieval calls.

### Step 4: Add the JS glue

zigdom's Zig modules call into JS functions provided by `zigdom.js`. Copy it
(and optionally `synth-worklet.js` for the retro soundtrack) into your
project:

```bash
curl -O https://raw.githubusercontent.com/ewaldhorn/zigdom/main/docs/zigdom.js
curl -O https://raw.githubusercontent.com/ewaldhorn/zigdom/main/docs/synth-worklet.js
```

Include them in your HTML and load your WASM binary with the built-in
`ZigDom.instantiate` helper:

```html
<script src="zigdom.js"></script>
<script type="module">
  ZigDom.instantiate("app.wasm").catch(err => {
    console.error("Zigdom failed to load:", err);
  });
</script>
```

### Step 5: Build

```bash
zig build
```

The demo builds with `ReleaseSmall` for a compact WASM binary (~24 KB).
Your WASM binary lands in `zig-out/bin/` by default. If you need it elsewhere
(like `docs/`), copy `demo/build.zig`'s install step or adapt the install
step in your own `build.zig`.

---

### Using a local path (without `zig fetch`)

If you want to point at a local checkout instead of fetching from GitHub,
add a path dependency to your `build.zig.zon`:

```zig
// in build.zig.zon
.zigdom = .{
    .path = "../zigdom",
},
```

Everything else stays the same — `b.dependency("zigdom", ...)` resolves
the local path automatically.

### Quick start code

```zig
const dom = @import("dom");

export fn zig_init() void {
    dom.init();  // must be called first — captures document/body/head handles

    const h1 = dom.createElement("h1");
    dom.setInnerText(h1, "Hello from Zig!");
    dom.addToBody(h1);
}
```

Or write it declaratively with the `html` builder:

```zig
const dom = @import("dom");
const html = @import("html");

export fn zig_init() void {
    dom.init();

    _ = html.div()
        .id("root")
        .child(html.h1().text("Hello from Zig!").build())
        .child(html.p().text("Rendered with zigdom.").build())
        .appendTo(dom.body);
}
```

The builder and handle-based API share the same underlying handle table and
can be mixed freely.

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

If you use `zig_set_interaction` for canvas touch/click coordinates, export
that function too:

```zig
export fn zig_set_interaction(x: i32, y: i32) void {
    // store x, y for the next callback invocation
}
```

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
- **Low-latency UI audio & dedicated synth thread** — The 1980s retro
  soundtrack synthesizer runs inside a dedicated browser `AudioWorklet` thread
  (`docs/synth-worklet.js`) to guarantee pop-free, stutter-free playback under heavy
  DOM and Canvas rendering. Meanwhile, short UI sound effects (like the 50ms button
  click) are pre-rendered directly into a static WASM buffer inside `src/sound.zig`.
  On first play, JavaScript wraps the WASM memory buffer in a zero-copy `Float32Array`
  view, copies it to a native AudioBuffer, and triggers it with sub-millisecond,
  hardware-accelerated latency. Both share a lazily-initialized browser `AudioContext`
  with decoupled node setup.
- **No GC** — No hidden allocations, no finalizers. All data lives in
  fixed-size global arrays in the WASM data segment.

## API

### `dom` — Core DOM

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

### `html` — Declarative HTML Builder

| Concern | Methods / Constructors |
|---|---|
| Builder struct | `Elm.handle` (the dom.Handle), `Elm.init("tag")` |
| Chain methods | `.id(str)`, `.class(str)`, `.text(str)`, `.html(str)`, `.attr(key,val)`, `.child(handle)`, `.appendTo(handle)`, `.on(event, cb_id)`, `.build()` |
| Structural tags | `div()`, `span()`, `p()`, `button()`, `a()` |
| Headings | `h1()`–`h6()` |
| Semantic | `article()`, `aside()`, `section()`, `nav()`, `header()`, `footer()`, `main_tag()` |
| Lists | `ul()`, `ol()`, `li()`, `dl()`, `dt()`, `dd()` |
| Inline text | `strong()`, `em()`, `code()`, `pre()`, `small()`, `mark()`, `b()`, `i()` |
| Form | `form()`, `input()`, `label()`, `select()`, `option()`, `textarea()`, `fieldset()`, `legend()` |
| Media | `img()`, `br()`, `hr()` |
| Table | `table()`, `thead()`, `tbody()`, `tr()`, `th()`, `td()` |
| Misc | `figure()`, `figcaption()`, `details()`, `summary()`, `blockquote()`, `cite()`, `time()` |

> [!NOTE]
> `.child()` accepts a `dom.Handle` — pass the result of `.build()` from a
> child sub-tree. `.appendTo()` accepts a parent `dom.Handle` and returns
> `*const Elm` for further chaining. Use `.on("click", cb_id)` to attach
> event listeners inline during construction.

### `canvas` — In-Memory Pixel Canvas

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

### `colour` — Colour Primitives

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
`randomColour()` and `Colour.convertToGrayscale` use an internal
xorshift64 PRNG seeded at 1337. Call `colour.seed(n)` with a non-zero
value to get a different random sequence.

### `sound` — Zero-Heap Sound Effects

| Concern | Functions / Types |
|---|---|
| Sound Effects | `fillClick(buf: []f32)` |
| Configuration | `SAMPLE_RATE` (44.1kHz) |

> [!NOTE]
> `sound.zig` now only provides the UI click generator (`fillClick`). The retro soundtrack synthesizer was ported to `docs/synth-worklet.js` (browser AudioWorklet) for dedicated audio-thread performance.

## License

MIT — see [LICENSE](LICENSE).
