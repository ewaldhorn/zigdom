const std = @import("std");

// ------------------------------------------------------------------------------------------------
// JS Handle — opaque reference to a live JS object (DOM element, document,
// etc.) stored in the JS-side handle table. 0 = null/invalid.
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
pub const Handle = u32;
pub const INVALID: Handle = 0;

// ------------------------------------------------------------------------------------------------
// Global element references (set by init())
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
pub var document: Handle = INVALID;
pub var body: Handle = INVALID;
pub var head: Handle = INVALID;

// ------------------------------------------------------------------------------------------------
// Scratch buffer for receiving strings back from JS (e.g. property values).
// Single global is safe in WASM — all code runs on one thread.
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
var scratch: [4096]u8 = undefined;

// ------------------------------------------------------------------------------------------------
// Imported JS functions (provided by zigdom.js)
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
extern fn dom_get_global(ptr: [*]const u8, len: usize) Handle;
extern fn dom_get_property(handle: Handle, key_ptr: [*]const u8, key_len: usize) Handle;

extern fn dom_create_element(ptr: [*]const u8, len: usize) Handle;
extern fn dom_append_child(parent: Handle, child: Handle) void;
extern fn dom_remove_all_children(elem: Handle) void;
extern fn dom_set_inner_text(elem: Handle, ptr: [*]const u8, len: usize) void;
extern fn dom_set_inner_html(elem: Handle, ptr: [*]const u8, len: usize) void;
extern fn dom_set_property_str(elem: Handle, key_ptr: [*]const u8, key_len: usize, val_ptr: [*]const u8, val_len: usize) void;
extern fn dom_get_property_str(elem: Handle, key_ptr: [*]const u8, key_len: usize, out_ptr: [*]u8, out_len: usize) usize;
extern fn dom_set_class_name(elem: Handle, ptr: [*]const u8, len: usize) void;
extern fn dom_class_list_add(elem: Handle, ptr: [*]const u8, len: usize) void;
extern fn dom_class_list_remove(elem: Handle, ptr: [*]const u8, len: usize) void;
extern fn dom_class_list_contains(elem: Handle, ptr: [*]const u8, len: usize) i32;
extern fn dom_set_display(elem: Handle, ptr: [*]const u8, len: usize) void;
extern fn dom_call_focus(elem: Handle) void;
extern fn dom_get_element_by_id(ptr: [*]const u8, len: usize) Handle;
extern fn dom_add_style_element(ptr: [*]const u8, len: usize) void;
extern fn dom_add_event_listener(elem: Handle, event_ptr: [*]const u8, event_len: usize, cb_id: u32) void;
extern fn dom_log(ptr: [*]const u8, len: usize) void;
extern fn dom_alert(ptr: [*]const u8, len: usize) void;

extern fn dom_canvas_create(parent: Handle, width: u32, height: u32) Handle;
extern fn dom_canvas_get_context(canvas: Handle) Handle;
extern fn dom_canvas_render(canvas: Handle, ctx: Handle, pixels_ptr: [*]const u8, width: u32, height: u32) void;
extern fn dom_start_animation_loop(cb_id: u32) void;
extern fn dom_ctx_begin_path(ctx: Handle) void;
extern fn dom_ctx_fill(ctx: Handle) void;
extern fn dom_ctx_arc(ctx: Handle, x: f64, y: f64, radius: f64, start: f64, end: f64, ccw: u32) void;
extern fn dom_ctx_fill_style(ctx: Handle, ptr: [*]const u8, len: usize) void;

// ------------------------------------------------------------------------------------------------
// Lifecycle
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
/// init — must be called once before any other dom function. Captures global
/// JS references (document, body, head) from the browser.
pub fn init() void {
    const doc_name = "document";
    const body_name = "body";
    const head_name = "head";
    document = dom_get_global(doc_name.ptr, doc_name.len);
    body = dom_get_property(document, body_name.ptr, body_name.len);
    head = dom_get_property(document, head_name.ptr, head_name.len);
}

// ------------------------------------------------------------------------------------------------
// Element CRUD
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
/// Creates a new HTML element of the given tag name.
pub fn createElement(tag: []const u8) Handle {
    return dom_create_element(tag.ptr, tag.len);
}

// ------------------------------------------------------------------------------------------------
pub fn createDiv() Handle {
    return createElement("div");
}

// ------------------------------------------------------------------------------------------------
pub fn createParagraph() Handle {
    return createElement("p");
}

// ------------------------------------------------------------------------------------------------
pub fn createParagraphWithText(text: []const u8) Handle {
    const p = createElement("p");
    dom_set_inner_text(p, text.ptr, text.len);
    return p;
}

// ------------------------------------------------------------------------------------------------
pub fn createButton(text: []const u8) Handle {
    const b = createElement("button");
    set(b, "type", "button");
    setInnerText(b, text);
    return b;
}

// ------------------------------------------------------------------------------------------------
pub fn createImg(src: []const u8) Handle {
    const img = createElement("img");
    set(img, "src", src);
    return img;
}

// ------------------------------------------------------------------------------------------------
// Element manipulation
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
pub fn addElementTo(target: Handle, elem: Handle) void {
    dom_append_child(target, elem);
}

// ------------------------------------------------------------------------------------------------
pub fn addToBody(elem: Handle) void {
    dom_append_child(body, elem);
}

// ------------------------------------------------------------------------------------------------
pub fn removeAllChildElementsFrom(target: Handle) void {
    dom_remove_all_children(target);
}

// ------------------------------------------------------------------------------------------------
pub fn getElementById(id: []const u8) Handle {
    return dom_get_element_by_id(id.ptr, id.len);
}

// ------------------------------------------------------------------------------------------------
/// Wraps an existing element in a new div with the given classes.
pub fn wrapElementWithNewDiv(element: Handle, classes: []const []const u8) Handle {
    const div = createDiv();
    for (classes) |cls| {
        dom_class_list_add(div, cls.ptr, cls.len);
    }
    dom_append_child(div, element);
    return div;
}

// ------------------------------------------------------------------------------------------------
// Visibility
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
pub fn hide(id: []const u8) void {
    const elem = dom_get_element_by_id(id.ptr, id.len);
    if (elem != INVALID) {
        const none_val = "none";
        dom_set_display(elem, none_val.ptr, none_val.len);
    }
}

// ------------------------------------------------------------------------------------------------
pub fn show(id: []const u8) void {
    const elem = dom_get_element_by_id(id.ptr, id.len);
    if (elem != INVALID) {
        const block_val = "block";
        dom_set_display(elem, block_val.ptr, block_val.len);
    }
}

// ------------------------------------------------------------------------------------------------
pub fn setFocus(id: []const u8) void {
    const elem = dom_get_element_by_id(id.ptr, id.len);
    if (elem != INVALID) {
        dom_call_focus(elem);
    }
}

// ------------------------------------------------------------------------------------------------
// Property access (string-based)
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
/// Retrieves a string property from an element by its ID.
///
/// WARNING: The returned slice points directly to a shared global scratch buffer.
/// If you need to retain the value across multiple calls to string-retrieval
/// functions (e.g., `getString` or `Handle.get`), you MUST copy/clone the slice.
pub fn getString(elem_id: []const u8, key: []const u8) []const u8 {
    const elem = dom_get_element_by_id(elem_id.ptr, elem_id.len);
    if (elem == INVALID) return "";
    const actual_len = dom_get_property_str(elem, key.ptr, key.len, &scratch, scratch.len);
    return scratch[0..@min(actual_len, scratch.len)];
}

// ------------------------------------------------------------------------------------------------
pub fn setValue(elem_id: []const u8, key: []const u8, value: []const u8) void {
    const elem = dom_get_element_by_id(elem_id.ptr, elem_id.len);
    if (elem != INVALID) {
        dom_set_property_str(elem, key.ptr, key.len, value.ptr, value.len);
    }
}

// ------------------------------------------------------------------------------------------------
// Handle-based property access
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
/// Sets a string property on an element by handle.
pub fn set(self: Handle, key: []const u8, value: []const u8) void {
    dom_set_property_str(self, key.ptr, key.len, value.ptr, value.len);
}

// ------------------------------------------------------------------------------------------------
/// Retrieves a string property from an element handle.
///
/// WARNING: The returned slice points to a shared global scratch buffer.
/// If you need to retain the value across multiple string-retrieval calls
/// you MUST copy/clone it first.
pub fn get(self: Handle, key: []const u8) []const u8 {
    const actual_len = dom_get_property_str(self, key.ptr, key.len, &scratch, scratch.len);
    return scratch[0..@min(actual_len, scratch.len)];
}

// ------------------------------------------------------------------------------------------------
/// Sets the inner text of an element.
pub fn setInnerText(self: Handle, text: []const u8) void {
    dom_set_inner_text(self, text.ptr, text.len);
}

// ------------------------------------------------------------------------------------------------
/// Sets the inner HTML of an element.
pub fn setInnerHTML(self: Handle, html: []const u8) void {
    dom_set_inner_html(self, html.ptr, html.len);
}

// ------------------------------------------------------------------------------------------------
/// Adds a CSS class to an element by handle.
pub fn addClassTo(self: Handle, class: []const u8) void {
    dom_class_list_add(self, class.ptr, class.len);
}

// ------------------------------------------------------------------------------------------------
/// Removes a CSS class from an element by handle.
pub fn removeClassFrom(self: Handle, class: []const u8) void {
    dom_class_list_remove(self, class.ptr, class.len);
}

// ------------------------------------------------------------------------------------------------
/// Replaces all CSS classes on an element with the given list.
pub fn replaceClasses(self: Handle, classes: []const []const u8) void {
    dom_set_class_name(self, "", 0);
    for (classes) |cls| dom_class_list_add(self, cls.ptr, cls.len);
}

// ------------------------------------------------------------------------------------------------
// Style (by element ID)
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
/// Adds a CSS class to an element looked up by its DOM id attribute.
pub fn addClass(elem_id: []const u8, class: []const u8) void {
    const elem = dom_get_element_by_id(elem_id.ptr, elem_id.len);
    if (elem != INVALID) dom_class_list_add(elem, class.ptr, class.len);
}

// ------------------------------------------------------------------------------------------------
/// Removes a CSS class from an element looked up by its DOM id attribute.
pub fn removeClass(elem_id: []const u8, class: []const u8) void {
    const elem = dom_get_element_by_id(elem_id.ptr, elem_id.len);
    if (elem != INVALID) dom_class_list_remove(elem, class.ptr, class.len);
}

// ------------------------------------------------------------------------------------------------
/// Injects a `<style>` element containing `css` into `document.head`.
pub fn addNewStyleElement(css: []const u8) void {
    dom_add_style_element(css.ptr, css.len);
}

// ------------------------------------------------------------------------------------------------
// Events
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
pub fn addEventListener(elem: Handle, event: []const u8, cb_id: u32) void {
    dom_add_event_listener(elem, event.ptr, event.len, cb_id);
}

// ------------------------------------------------------------------------------------------------
/// Convenience: look up element by ID, then add event listener.
pub fn addEventListenerById(id: []const u8, event: []const u8, cb_id: u32) void {
    const elem = dom_get_element_by_id(id.ptr, id.len);
    if (elem != INVALID) {
        dom_add_event_listener(elem, event.ptr, event.len, cb_id);
    }
}

// ------------------------------------------------------------------------------------------------
// Logging
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
/// Logs one or more messages to the browser console, joined with spaces.
/// If the total joined length fits in the shared scratch buffer, all messages
/// are written as a single `console.log` call. Otherwise each message is
/// logged individually — note that this fallback omits the spaces between them.
pub fn log(messages: []const []const u8) void {
    var total: usize = 0;
    for (messages, 0..) |msg, i| {
        if (i > 0) total += 1;
        total += msg.len;
    }
    if (total < scratch.len) {
        var pos: usize = 0;
        for (messages, 0..) |msg, i| {
            if (i > 0) {
                scratch[pos] = ' ';
                pos += 1;
            }
            @memcpy(scratch[pos..][0..msg.len], msg);
            pos += msg.len;
        }
        dom_log(scratch[0..pos].ptr, pos);
    } else {
        // Fallback: individual calls without spaces (total exceeds scratch buffer).
        for (messages) |msg| dom_log(msg.ptr, msg.len);
    }
}

// ------------------------------------------------------------------------------------------------
// Alert
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
pub fn showAlert(msg: []const u8) void {
    dom_alert(msg.ptr, msg.len);
}

// ------------------------------------------------------------------------------------------------
// Canvas & Context 2D Utilities
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
pub fn canvasCreate(parent: Handle, width: u32, height: u32) Handle {
    return dom_canvas_create(parent, width, height);
}

// ------------------------------------------------------------------------------------------------
pub fn canvasGetContext(canvas: Handle) Handle {
    return dom_canvas_get_context(canvas);
}

// ------------------------------------------------------------------------------------------------
pub fn canvasRender(canvas: Handle, ctx: Handle, pixels_ptr: [*]const u8, width: u32, height: u32) void {
    dom_canvas_render(canvas, ctx, pixels_ptr, width, height);
}

// ------------------------------------------------------------------------------------------------
pub fn startAnimationLoop(cb_id: u32) void {
    dom_start_animation_loop(cb_id);
}

// ------------------------------------------------------------------------------------------------
pub const Context2D = struct {
    ctx: Handle,

    // --------------------------------------------------------------------------------------------
    // Methods
    // --------------------------------------------------------------------------------------------

    // --------------------------------------------------------------------------------------------
    pub fn beginPath(self: Context2D) void {
        dom_ctx_begin_path(self.ctx);
    }

    // --------------------------------------------------------------------------------------------
    pub fn fill(self: Context2D) void {
        dom_ctx_fill(self.ctx);
    }

    // --------------------------------------------------------------------------------------------
    pub fn arc(self: Context2D, x: f64, y: f64, radius: f64, startAngle: f64, endAngle: f64, ccw: bool) void {
        dom_ctx_arc(self.ctx, x, y, radius, startAngle, endAngle, if (ccw) 1 else 0);
    }

    // --------------------------------------------------------------------------------------------
    pub fn fillStyle(self: Context2D, style: []const u8) void {
        dom_ctx_fill_style(self.ctx, style.ptr, style.len);
    }
};
