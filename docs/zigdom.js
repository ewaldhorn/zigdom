// zigdom.js — JS glue for Zig WASM DOM manipulation
// Replaces TinyGo's wasm_exec.js with a minimal bridge.
// Provides imports for DOM operations and handles the callback table.
//
// The WASM module exports its own memory (created by the Zig compiler).
// JS-side import functions read/write WASM memory via the exported buffer.
// Use a mutable `wasmMemory` variable — set after instantiation, but
// captured by closure in the import object defined before instantiation.

(() => {
  "use strict";

  const decoder = new TextDecoder("utf-8");
  const encoder = new TextEncoder("utf-8");

  // ---------------------------------------------------------------
  // JS Value Handle Table
  // Stores references to live JS objects (DOM elements, document, etc.)
  // indexed by integer handles passed to/from Zig.
  // Index 0 is always null / invalid.
  // ---------------------------------------------------------------
  const jsValues = [null];
  let nextHandle = 1;

  function getHandle(value) {
    const id = nextHandle++;
    jsValues[id] = value;
    return id;
  }

  // ---------------------------------------------------------------
  // Callback Table
  // Zig registers callback functions by ID. JS invokes them through
  // the exported `zig_invoke_callback(id)`.
  // ---------------------------------------------------------------
  const callbacks = [];

  // ---------------------------------------------------------------
  // String helpers
  // ---------------------------------------------------------------
  function readStr(mem, ptr, len) {
    return decoder.decode(new Uint8Array(mem.buffer, ptr, len));
  }

  function writeStr(mem, ptr, str) {
    const encoded = encoder.encode(str);
    new Uint8Array(mem.buffer, ptr, encoded.length).set(encoded);
    return encoded.length;
  }

  // ---------------------------------------------------------------
  // WASM Instantiation
  // ---------------------------------------------------------------
  globalThis.ZigDom = {
    instantiate: async function (wasmUrl) {
      // The WASM module exports its own memory (Zig compiler sets the
      // initial page count based on data segments + stack). We do NOT
      // create a Memory here — instead we'll grab it from exports after
      // instantiation.
      let wasmMemory;

      const importObject = {
        env: {
          // --- Generic JS value access ---

          dom_get_global: (ptr, len) => {
            return getHandle(globalThis[readStr(wasmMemory, ptr, len)]);
          },

          dom_get_property: (handle, keyPtr, keyLen) => {
            return getHandle(
              jsValues[handle][readStr(wasmMemory, keyPtr, keyLen)],
            );
          },

          // --- Element creation ---

          dom_create_element: (tagPtr, tagLen) => {
            return getHandle(
              document.createElement(readStr(wasmMemory, tagPtr, tagLen)),
            );
          },

          // --- Element manipulation ---

          dom_append_child: (parent, child) => {
            jsValues[parent].appendChild(jsValues[child]);
          },

          dom_remove_all_children: (elem) => {
            jsValues[elem].replaceChildren();
          },

          dom_set_inner_text: (elem, ptr, len) => {
            jsValues[elem].innerText = readStr(wasmMemory, ptr, len);
          },

          dom_set_inner_html: (elem, ptr, len) => {
            jsValues[elem].innerHTML = readStr(wasmMemory, ptr, len);
          },

          dom_set_property_str: (
            elem,
            keyPtr,
            keyLen,
            valPtr,
            valLen,
          ) => {
            jsValues[elem][readStr(wasmMemory, keyPtr, keyLen)] = readStr(
              wasmMemory,
              valPtr,
              valLen,
            );
          },

          dom_get_property_str: (elem, keyPtr, keyLen, outPtr, outLen) => {
            const key = readStr(wasmMemory, keyPtr, keyLen);
            const val = String(jsValues[elem][key]);
            return writeStr(wasmMemory, outPtr, val);
          },

          dom_set_class_name: (elem, ptr, len) => {
            jsValues[elem].className = readStr(wasmMemory, ptr, len);
          },

          dom_class_list_add: (elem, ptr, len) => {
            jsValues[elem].classList.add(readStr(wasmMemory, ptr, len));
          },

          dom_class_list_remove: (elem, ptr, len) => {
            jsValues[elem].classList.remove(readStr(wasmMemory, ptr, len));
          },

          dom_class_list_contains: (elem, ptr, len) => {
            return jsValues[elem].classList.contains(
              readStr(wasmMemory, ptr, len),
            )
              ? 1
              : 0;
          },

          dom_set_display: (elem, ptr, len) => {
            jsValues[elem].style.display = readStr(wasmMemory, ptr, len);
          },

          dom_call_focus: (elem) => {
            jsValues[elem].focus();
          },

          dom_get_element_by_id: (ptr, len) => {
            const el = document.getElementById(
              readStr(wasmMemory, ptr, len),
            );
            return el ? getHandle(el) : 0;
          },

          // --- Style injection ---

          dom_add_style_element: (ptr, len) => {
            const style = document.createElement("style");
            style.type = "text/css";
            style.innerHTML = readStr(wasmMemory, ptr, len);
            document.head.appendChild(style);
          },

          // --- Events ---

          dom_add_event_listener: (elem, eventPtr, eventLen, cbId) => {
            const event = readStr(wasmMemory, eventPtr, eventLen);
            jsValues[elem].addEventListener(event, function () {
              wasmExports.zig_invoke_callback(cbId);
            });
          },

          // --- Canvas & Context 2D ---

          dom_canvas_create: (parent, width, height) => {
            const parentEl = jsValues[parent];
            const canvas = document.createElement("canvas");
            canvas.width = width;
            canvas.height = height;
            parentEl.appendChild(canvas);
            return getHandle(canvas);
          },

          dom_canvas_get_context: (canvas) => {
            const canvasEl = jsValues[canvas];
            const ctx = canvasEl.getContext("2d");
            return getHandle(ctx);
          },

          dom_canvas_render: (canvas, ctx, pixelsPtr, width, height) => {
            const ctxEl = jsValues[ctx];
            // Wrap WASM memory directly without copying!
            const array = new Uint8ClampedArray(wasmMemory.buffer, pixelsPtr, width * height * 4);
            const imgData = new ImageData(array, width, height);
            ctxEl.putImageData(imgData, 0, 0);
          },

          dom_start_animation_loop: (cbId) => {
            const tick = () => {
              wasmExports.zig_invoke_callback(cbId);
              requestAnimationFrame(tick);
            };
            requestAnimationFrame(tick);
          },

          dom_ctx_begin_path: (ctx) => {
            jsValues[ctx].beginPath();
          },

          dom_ctx_fill: (ctx) => {
            jsValues[ctx].fill();
          },

          dom_ctx_arc: (ctx, x, y, radius, startAngle, endAngle, ccw) => {
            jsValues[ctx].arc(x, y, radius, startAngle, endAngle, ccw === 1);
          },

          dom_ctx_fill_style: (ctx, ptr, len) => {
            jsValues[ctx].fillStyle = readStr(wasmMemory, ptr, len);
          },

          // --- Utilities ---

          dom_log: (ptr, len) => {
            console.log(readStr(wasmMemory, ptr, len));
          },

          dom_alert: (ptr, len) => {
            alert(readStr(wasmMemory, ptr, len));
          },
        },
      };

      // Fetch and instantiate the WASM module
      const response = await fetch(wasmUrl);
      const bytes = await response.arrayBuffer();
      const wasm = await WebAssembly.instantiate(bytes, importObject);
      const wasmExports = wasm.instance.exports;

      // Grab the WASM-exported memory — all import functions reference
      // the `wasmMemory` variable by closure, so they'll now use the
      // correct buffer.
      wasmMemory = wasmExports.memory;

      // Initialize: runs the demo
      wasmExports.zig_init();
    },
  };
})();
