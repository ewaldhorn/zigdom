// ------------------------------------------------------------------------------------------------
// zigdom.js — JS glue for Zig WASM DOM manipulation
// Replaces TinyGo's wasm_exec.js with a minimal bridge.
// Provides imports for DOM operations and handles the callback table.
//
// The WASM module exports its own memory (created by the Zig compiler).
// JS-side import functions read/write WASM memory via the exported buffer.
// Use a mutable `wasmMemory` variable — set after instantiation, but
// captured by closure in the import object defined before instantiation.
// ------------------------------------------------------------------------------------------------

(() => {
  "use strict";

  // ----------------------------------------------------------------------------------------------
  const decoder = new TextDecoder("utf-8");
  const encoder = new TextEncoder("utf-8");

  // ----------------------------------------------------------------------------------------------
  // JS Value Handle Table
  // Stores references to live JS objects (DOM elements, document, etc.)
  // indexed by integer handles passed to/from Zig.
  // Index 0 is always null / invalid.
  // ----------------------------------------------------------------------------------------------

  // ----------------------------------------------------------------------------------------------
  const jsValues = [null];
  let nextHandle = 1;

  // ----------------------------------------------------------------------------------------------
  function getHandle(value) {
    const id = nextHandle++;
    jsValues[id] = value;
    return id;
  }

  // ----------------------------------------------------------------------------------------------
  // String helpers (low-level — require explicit memory argument)
  // ----------------------------------------------------------------------------------------------

  // ----------------------------------------------------------------------------------------------
  function readStr(mem, ptr, len) {
    return decoder.decode(new Uint8Array(mem.buffer, ptr, len));
  }

  // ----------------------------------------------------------------------------------------------
  function writeStr(mem, ptr, str, maxLen) {
    const encoded = encoder.encode(str);
    const len = maxLen !== undefined ? Math.min(encoded.length, maxLen) : encoded.length;
    new Uint8Array(mem.buffer, ptr, len).set(encoded.subarray(0, len));
    return len;
  }

  // ----------------------------------------------------------------------------------------------
  // WASM Instantiation
  // ----------------------------------------------------------------------------------------------

  // ----------------------------------------------------------------------------------------------
  globalThis.ZigDom = {
    instantiate: async function (wasmUrl) {
      // ------------------------------------------------------------------------------------------
      // The WASM module exports its own memory (Zig compiler sets the
      // initial page count based on data segments + stack). We do NOT
      // create a Memory here — instead we'll grab it from exports after
      // instantiation.
      // ------------------------------------------------------------------------------------------
      let wasmMemory;
      let wasmExports;

      // ------------------------------------------------------------------------------------------
      // Convenience helpers that close over wasmMemory — eliminates the
      // repetitive `readStr(wasmMemory, ptr, len)` at every call site.
      // ------------------------------------------------------------------------------------------
      function getStr(ptr, len) {
        return decoder.decode(new Uint8Array(wasmMemory.buffer, ptr, len));
      }
      function putStr(ptr, str, maxLen) {
        const encoded = encoder.encode(str);
        const len = maxLen !== undefined ? Math.min(encoded.length, maxLen) : encoded.length;
        new Uint8Array(wasmMemory.buffer, ptr, len).set(encoded.subarray(0, len));
        return len;
      }

      // ------------------------------------------------------------------------------------------
      const importObject = {
        env: {
          // --------------------------------------------------------------------------------------
          // Generic JS value access
          // --------------------------------------------------------------------------------------

          dom_get_global: (ptr, len) => {
            const val = globalThis[getStr(ptr, len)];
            return (val !== undefined && val !== null) ? getHandle(val) : 0;
          },

          dom_get_property: (handle, keyPtr, keyLen) => {
            return getHandle(jsValues[handle][getStr(keyPtr, keyLen)]);
          },

          // --------------------------------------------------------------------------------------
          // Element creation
          // --------------------------------------------------------------------------------------

          dom_create_element: (tagPtr, tagLen) => {
            return getHandle(document.createElement(getStr(tagPtr, tagLen)));
          },

          // --------------------------------------------------------------------------------------
          // Element manipulation
          // --------------------------------------------------------------------------------------

          dom_append_child: (parent, child) => {
            jsValues[parent].appendChild(jsValues[child]);
          },

          dom_remove_all_children: (elem) => {
            jsValues[elem].replaceChildren();
          },

          dom_set_inner_text: (elem, ptr, len) => {
            jsValues[elem].innerText = getStr(ptr, len);
          },

          dom_set_inner_html: (elem, ptr, len) => {
            jsValues[elem].innerHTML = getStr(ptr, len);
          },

          dom_set_property_str: (elem, keyPtr, keyLen, valPtr, valLen) => {
            jsValues[elem][getStr(keyPtr, keyLen)] = getStr(valPtr, valLen);
          },

          dom_get_property_str: (elem, keyPtr, keyLen, outPtr, outLen) => {
            const key = getStr(keyPtr, keyLen);
            const val = String(jsValues[elem][key]);
            return putStr(outPtr, val, outLen);
          },

          dom_set_class_name: (elem, ptr, len) => {
            jsValues[elem].className = getStr(ptr, len);
          },

          dom_class_list_add: (elem, ptr, len) => {
            jsValues[elem].classList.add(getStr(ptr, len));
          },

          dom_class_list_remove: (elem, ptr, len) => {
            jsValues[elem].classList.remove(getStr(ptr, len));
          },

          dom_class_list_contains: (elem, ptr, len) => {
            return jsValues[elem].classList.contains(getStr(ptr, len))
              ? 1
              : 0;
          },

          dom_set_display: (elem, ptr, len) => {
            jsValues[elem].style.display = getStr(ptr, len);
          },

          dom_call_focus: (elem) => {
            jsValues[elem].focus();
          },

          dom_get_element_by_id: (ptr, len) => {
            const el = document.getElementById(getStr(ptr, len));
            return el ? getHandle(el) : 0;
          },

          // --------------------------------------------------------------------------------------
          // Style injection
          // --------------------------------------------------------------------------------------

          dom_add_style_element: (ptr, len) => {
            const style = document.createElement("style");
            style.type = "text/css";
            style.innerHTML = getStr(ptr, len);
            document.head.appendChild(style);
          },

          // --------------------------------------------------------------------------------------
          // Events
          // --------------------------------------------------------------------------------------

          dom_add_event_listener: (elem, eventPtr, eventLen, cbId) => {
            const event = getStr(eventPtr, eventLen);
            jsValues[elem].addEventListener(event, () => {
              wasmExports.zig_invoke_callback(cbId);
            });
          },

          // --------------------------------------------------------------------------------------
          // Canvas & Context 2D
          // --------------------------------------------------------------------------------------

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
            jsValues[ctx].fillStyle = getStr(ptr, len);
          },

          // --------------------------------------------------------------------------------------
          // Utilities
          // --------------------------------------------------------------------------------------

          dom_log: (ptr, len) => {
            console.log(getStr(ptr, len));
          },

          dom_alert: (ptr, len) => {
            alert(getStr(ptr, len));
          },
        },
      };

      // ------------------------------------------------------------------------------------------
      // Fetch and instantiate the WASM module using streaming compilation if available
      // ------------------------------------------------------------------------------------------
      let wasm;
      if (typeof WebAssembly.instantiateStreaming === "function") {
        wasm = await WebAssembly.instantiateStreaming(
          fetch(wasmUrl),
          importObject,
        );
      } else {
        const response = await fetch(wasmUrl);
        const bytes = await response.arrayBuffer();
        wasm = await WebAssembly.instantiate(bytes, importObject);
      }

      wasmExports = wasm.instance.exports;

      // ------------------------------------------------------------------------------------------
      // Grab the WASM-exported memory — all import functions reference
      // the `wasmMemory` variable by closure, so they'll now use the
      // correct buffer.
      // ------------------------------------------------------------------------------------------
      wasmMemory = wasmExports.memory;

      // ------------------------------------------------------------------------------------------
      // Web Audio API Synth Bridge (AudioWorkletNode — runs on dedicated audio thread)
      // ------------------------------------------------------------------------------------------
      let audioCtx = null;
      let synthNode = null;
      let gainNode = null;
      let audioPlaying = false;
      let globalVolume = 0.2;

      globalThis.toggleAudio = async function () {
        if (!audioCtx) {
          // Initialize AudioContext on user gesture
          audioCtx = new (window.AudioContext || window.webkitAudioContext)();
        }

        if (!synthNode) {
          // Load the AudioWorkletProcessor module (dedicated audio thread)
          await audioCtx.audioWorklet.addModule('synth-worklet.js');

          // Create the synth AudioWorkletNode
          synthNode = new AudioWorkletNode(audioCtx, 'synth-worklet');

          // Create standard GainNode for hardware-accelerated volume control
          gainNode = audioCtx.createGain();
          gainNode.gain.setValueAtTime(globalVolume, audioCtx.currentTime);

          // Connect AudioWorkletNode -> GainNode -> Destination
          synthNode.connect(gainNode);
          gainNode.connect(audioCtx.destination);
        }

        if (audioCtx.state === "suspended") {
          await audioCtx.resume();
        }

        audioPlaying = !audioPlaying;

        // Send play state to the worklet's dedicated audio thread
        synthNode.port.postMessage({ type: 'play', value: audioPlaying });

        const btn = document.getElementById("audioToggleButton");
        if (btn) {
          btn.innerText = audioPlaying ? "🔊 Mute Soundtrack" : "🔇 Play Soundtrack";
          btn.classList.toggle("playing", audioPlaying);
        }
      };

      globalThis.changeVolume = function (val) {
        globalVolume = parseFloat(val);
        if (gainNode && audioCtx) {
          // Standard: transition gain value at target time to prevent popping/zipper noise
          gainNode.gain.setValueAtTime(globalVolume, audioCtx.currentTime);
        }
        const label = document.getElementById("volumeLabel");
        if (label) {
          const pct = Math.round(globalVolume * 100);
          label.innerText = globalVolume === 0 ? "Vol: OFF" : `Vol: ${pct}%`;
        }
      };

      // ------------------------------------------------------------------------------------------
      // Click sound — pre-rendered 50ms UI click from Zig WASM
      // ------------------------------------------------------------------------------------------
      let clickAudioBuffer = null; // AudioBuffer, created lazily on first click

      globalThis.playClickSound = function () {
        // Lazy AudioContext (always called from user gesture, so autoplay policy OK)
        if (!audioCtx) {
          audioCtx = new (window.AudioContext || window.webkitAudioContext)();
        }
        if (audioCtx.state === "suspended") {
          audioCtx.resume();
        }

        // Lazy AudioBuffer creation from pre-rendered WASM samples
        if (!clickAudioBuffer) {
          const ptr = wasmExports.zig_get_click_buffer();
          const len = wasmExports.zig_get_click_buffer_len();
          const samples = new Float32Array(wasmMemory.buffer, ptr, len);
          clickAudioBuffer = audioCtx.createBuffer(1, len, 44100);
          clickAudioBuffer.copyToChannel(samples, 0);
        }

        const source = audioCtx.createBufferSource();
        source.buffer = clickAudioBuffer;
        source.connect(audioCtx.destination);
        source.start();
      };

      // ------------------------------------------------------------------------------------------
      // Initialize: runs the demo
      // ------------------------------------------------------------------------------------------
      wasmExports.zig_init();

      // ------------------------------------------------------------------------------------------
      // Wire click sound to action buttons (skip audioToggleButton — that's the synth)
      // ------------------------------------------------------------------------------------------
      ['addSomethingButton', 'clearAsideButton', 'refreshButton'].forEach(function (id) {
        const btn = document.getElementById(id);
        if (btn) btn.addEventListener('click', playClickSound);
      });

      // ------------------------------------------------------------------------------------------
      // Touch / Click interaction for the physics canvas (canvas two).
      // After zig_init, Zig has created the canvas elements.
      // The physics canvas is the sole child of #canvasTwoDiv.
      // ------------------------------------------------------------------------------------------
      const canvasTwoDiv = document.getElementById("canvasTwoDiv");
      if (canvasTwoDiv) {
        const physicsCanvas = canvasTwoDiv.querySelector("canvas");
        if (physicsCanvas) {
          // --------------------------------------------------------------------------------------
          // Show controls as flex (CSS sets display:none by default, Zig calls show() which sets block)
          // Override to flex so the buttons wrap nicely.
          // --------------------------------------------------------------------------------------
          const controls = document.getElementById("controls");
          if (controls) controls.style.display = "flex";

          function handleInteraction(clientX, clientY) {
            const rect = physicsCanvas.getBoundingClientRect();
            if (rect.width === 0 || rect.height === 0) return;
            // Map from CSS pixels to canvas pixel space
            const scaleX = physicsCanvas.width / rect.width;
            const scaleY = physicsCanvas.height / rect.height;
            const x = Math.round((clientX - rect.left) * scaleX);
            const y = Math.round((clientY - rect.top) * scaleY);
            wasmExports.zig_set_interaction(x, y);
            wasmExports.zig_invoke_callback(4);
          }

          physicsCanvas.addEventListener("mousedown", (e) => {
            e.preventDefault();
            handleInteraction(e.clientX, e.clientY);
          });

          physicsCanvas.addEventListener("touchstart", (e) => {
            e.preventDefault();
            const touch = e.touches[0];
            handleInteraction(touch.clientX, touch.clientY);
          }, { passive: false });
        }
      }
    },
  };
})();
