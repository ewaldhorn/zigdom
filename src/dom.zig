const std = @import("std");

// ---------------------------------------------------------------------------
// JS Handle — opaque reference to a live JS object (DOM element, document,
// etc.) stored in the JS-side handle table. 0 = null/invalid.
// ---------------------------------------------------------------------------
pub const Handle = u32;
pub const INVALID: Handle = 0;

// ---------------------------------------------------------------------------
// Global element references (set by init())
// ---------------------------------------------------------------------------
pub var document: Handle = INVALID;
pub var body: Handle = INVALID;
pub var head: Handle = INVALID;

// ---------------------------------------------------------------------------
// Scratch buffer for receiving strings back from JS (e.g. property values).
// Single global is safe in WASM — all code runs on one thread.
// ---------------------------------------------------------------------------
var scratch: [4096]u8 = undefined;

// ---------------------------------------------------------------------------
// Imported JS functions (provided by zigdom.js)
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// init — must be called once before any other dom function. Captures global
// JS references (document, body, head) from the browser.
// ---------------------------------------------------------------------------
pub fn init() void {
    document = dom_get_global("document", 8);
    body = dom_get_property(document, "body", 4);
    head = dom_get_property(document, "head", 4);
}

// ---------------------------------------------------------------------------
// Element CRUD
// ---------------------------------------------------------------------------

/// Creates a new HTML element of the given tag name.
pub fn createElement(tag: []const u8) Handle {
    return dom_create_element(tag.ptr, tag.len);
}

pub fn createDiv() Handle {
    return createElement("div");
}

pub fn createParagraph() Handle {
    return createElement("p");
}

pub fn createParagraphWithText(text: []const u8) Handle {
    const p = createElement("p");
    dom_set_inner_text(p, text.ptr, text.len);
    return p;
}

pub fn createButton(text: []const u8) Handle {
    const b = createElement("button");
    b.set("type", "button");
    b.setInnerText(text);
    return b;
}

pub fn createImg(src: []const u8) Handle {
    const img = createElement("img");
    img.set("src", src);
    return img;
}

// ---------------------------------------------------------------------------
// Element manipulation
// ---------------------------------------------------------------------------

pub fn addElementTo(target: Handle, elem: Handle) void {
    dom_append_child(target, elem);
}

pub fn addToBody(elem: Handle) void {
    dom_append_child(body, elem);
}

pub fn removeAllChildElementsFrom(target: Handle) void {
    dom_remove_all_children(target);
}

pub fn getElementById(id: []const u8) Handle {
    return dom_get_element_by_id(id.ptr, id.len);
}

/// Wraps an existing element in a new div with the given classes.
pub fn wrapElementWithNewDiv(element: Handle, classes: []const []const u8) Handle {
    const div = createDiv();
    if (classes.len > 0) {
        var buf: [256]u8 = undefined;
        var i: usize = 0;
        for (classes, 0..) |cls, idx| {
            if (idx > 0) {
                buf[i] = ' ';
                i += 1;
            }
            @memcpy(buf[i..][0..cls.len], cls);
            i += cls.len;
        }
        dom_set_class_name(div, buf[0..i].ptr, i);
    }
    dom_append_child(div, element);
    return div;
}

// ---------------------------------------------------------------------------
// Visibility
// ---------------------------------------------------------------------------

pub fn hide(id: []const u8) void {
    const elem = dom_get_element_by_id(id.ptr, id.len);
    if (elem != INVALID) {
        dom_set_display(elem, "none", 4);
    }
}

pub fn show(id: []const u8) void {
    const elem = dom_get_element_by_id(id.ptr, id.len);
    if (elem != INVALID) {
        dom_set_display(elem, "block", 5);
    }
}

pub fn setFocus(id: []const u8) void {
    const elem = dom_get_element_by_id(id.ptr, id.len);
    if (elem != INVALID) {
        dom_call_focus(elem);
    }
}

// ---------------------------------------------------------------------------
// Property access (string-based)
// ---------------------------------------------------------------------------

pub fn getString(elem_id: []const u8, key: []const u8) []const u8 {
    const elem = dom_get_element_by_id(elem_id.ptr, elem_id.len);
    if (elem == INVALID) return "";
    const actual_len = dom_get_property_str(elem, key.ptr, key.len, &scratch, scratch.len);
    return scratch[0..@min(actual_len, scratch.len)];
}

pub fn setValue(elem_id: []const u8, key: []const u8, value: []const u8) void {
    const elem = dom_get_element_by_id(elem_id.ptr, elem_id.len);
    if (elem != INVALID) {
        dom_set_property_str(elem, key.ptr, key.len, value.ptr, value.len);
    }
}

// ---------------------------------------------------------------------------
// Handle-based property access (more efficient)
// ---------------------------------------------------------------------------

pub fn Handle_set(self: Handle, comptime key: []const u8, value: []const u8) void {
    dom_set_property_str(self, key, key.len, value.ptr, value.len);
}

pub fn Handle_get(self: Handle, key: []const u8) []const u8 {
    const actual_len = dom_get_property_str(self, key.ptr, key.len, &scratch, scratch.len);
    return scratch[0..@min(actual_len, scratch.len)];
}

pub fn Handle_setInnerText(self: Handle, text: []const u8) void {
    dom_set_inner_text(self, text.ptr, text.len);
}

pub fn Handle_setInnerHTML(self: Handle, html: []const u8) void {
    dom_set_inner_html(self, html.ptr, html.len);
}

pub fn Handle_addClass(self: Handle, class: []const u8) void {
    dom_class_list_add(self, class.ptr, class.len);
}

pub fn Handle_removeClass(self: Handle, class: []const u8) void {
    dom_class_list_remove(self, class.ptr, class.len);
}

pub fn Handle_replaceClasses(self: Handle, classes: []const []const u8) void {
    if (classes.len == 0) {
        dom_set_class_name(self, "", 0);
        return;
    }
    var buf: [256]u8 = undefined;
    var i: usize = 0;
    for (classes, 0..) |cls, idx| {
        if (idx > 0) {
            buf[i] = ' ';
            i += 1;
        }
        @memcpy(buf[i..][0..cls.len], cls);
        i += cls.len;
    }
    dom_set_class_name(self, buf[0..i].ptr, i);
}

// ---------------------------------------------------------------------------
// Style
// ---------------------------------------------------------------------------

pub fn addClass(elem_id: []const u8, class: []const u8) void {
    const elem = dom_get_element_by_id(elem_id.ptr, elem_id.len);
    if (elem != INVALID) {
        dom_class_list_add(elem, class.ptr, class.len);
    }
}

pub fn removeClass(elem_id: []const u8, class: []const u8) void {
    const elem = dom_get_element_by_id(elem_id.ptr, elem_id.len);
    if (elem != INVALID) {
        dom_class_list_remove(elem, class.ptr, class.len);
    }
}

pub fn addNewStyleElement(css: []const u8) void {
    dom_add_style_element(css.ptr, css.len);
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

pub fn addEventListener(elem: Handle, event: []const u8, cb_id: u32) void {
    dom_add_event_listener(elem, event.ptr, event.len, cb_id);
}

/// Convenience: look up element by ID, then add event listener.
pub fn addEventListenerById(id: []const u8, event: []const u8, cb_id: u32) void {
    const elem = dom_get_element_by_id(id.ptr, id.len);
    if (elem != INVALID) {
        dom_add_event_listener(elem, event.ptr, event.len, cb_id);
    }
}

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

pub fn log(messages: []const []const u8) void {
    // Join messages with space (like the original)
    var total: usize = 0;
    for (messages, 0..) |msg, i| {
        if (i > 0) total += 1;
        total += msg.len;
    }

    // If total fits in scratch, join there; otherwise call per-message
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
        for (messages) |msg| {
            dom_log(msg.ptr, msg.len);
        }
    }
}

// ---------------------------------------------------------------------------
// Alert
// ---------------------------------------------------------------------------

pub fn showAlert(msg: []const u8) void {
    dom_alert(msg.ptr, msg.len);
}

// ===========================================================================
// Extension methods for Handle
// ===========================================================================

pub fn set(self: Handle, comptime key: []const u8, value: []const u8) void {
    Handle_set(self, key, value);
}

pub fn get(self: Handle, key: []const u8) []const u8 {
    return Handle_get(self, key);
}

pub fn setInnerText(self: Handle, text: []const u8) void {
    Handle_setInnerText(self, text);
}

pub fn setInnerHTML(self: Handle, html: []const u8) void {
    Handle_setInnerHTML(self, html);
}

pub fn addClass2(self: Handle, class: []const u8) void {
    Handle_addClass(self, class);
}

pub fn removeClass2(self: Handle, class: []const u8) void {
    Handle_removeClass(self, class);
}

pub fn replaceClasses(self: Handle, classes: []const []const u8) void {
    Handle_replaceClasses(self, classes);
}
