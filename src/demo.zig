const std = @import("std");
const dom = @import("dom.zig");

// ---------------------------------------------------------------------------
const body_style = @embedFile("bodystyle.css");
const dommie_text = @embedFile("zigdom.txt");
const VERSION = "0.0.1a";
const NAME = "Zigdom Demo";

// ---------------------------------------------------------------------------
var is_ready: bool = false;
var boo_counter: u32 = 0;
var application_container: dom.Handle = dom.INVALID;
var article_element: dom.Handle = dom.INVALID;
var aside_element: dom.Handle = dom.INVALID;

// ---------------------------------------------------------------------------
const colours = [_][]const u8{ "red", "blue", "orange" };
const sizes = [_][]const u8{ "large", "larger", "xlarge" };

// ---------------------------------------------------------------------------
// Simple deterministic PRNG for WASM (no external entropy needed for demo)
var rng_state: u64 = 42;

// ---------------------------------------------------------------------------
fn nextRandom() u32 {
    // xorshift64*
    rng_state ^= rng_state << 13;
    rng_state ^= rng_state >> 7;
    rng_state ^= rng_state << 17;
    return @truncate(rng_state);
}

// ---------------------------------------------------------------------------
fn randomColour() []const u8 {
    return colours[nextRandom() % colours.len];
}

// ---------------------------------------------------------------------------
fn randomSize() []const u8 {
    return sizes[nextRandom() % sizes.len];
}

// ---------------------------------------------------------------------------
// Callback dispatch — exported so JS can call into Zig from event listeners.
// The JS side calls zig_invoke_callback(id) when a registered DOM event fires.
// ---------------------------------------------------------------------------
export fn zig_invoke_callback(id: u32) void {
    switch (id) {
        0 => onAddSomethingClick(),
        1 => onClearAsideClick(),
        else => {},
    }
}

// ---------------------------------------------------------------------------
fn onAddSomethingClick() void {
    if (!is_ready) return;
    if (nextRandom() % 2 == 0) {
        addBoo();
    } else {
        addRandomParagraph();
    }
}

// ---------------------------------------------------------------------------
fn onClearAsideClick() void {
    if (!is_ready) return;
    dom.removeAllChildElementsFrom(aside_element);
}

// ---------------------------------------------------------------------------
fn addBoo() void {
    boo_counter += 1;
    var buf: [32]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "Boo! ({d})", .{boo_counter}) catch "Boo!";
    const p = dom.createParagraphWithText(text);
    dom.addElementTo(aside_element, p);
}

// ---------------------------------------------------------------------------
fn addRandomParagraph() void {
    const p = dom.createParagraphWithText("This is some text");
    const wrapped = dom.wrapElementWithNewDiv(p, &.{ randomColour(), randomSize() });
    dom.addElementTo(aside_element, wrapped);
}

// ---------------------------------------------------------------------------
// toggleElements — port of original demo/main.go toggleElements()
// ---------------------------------------------------------------------------
fn toggleElements() void {
    dom.hide("loading");
    dom.show("controls");
    dom.show("information");
}

// ---------------------------------------------------------------------------
// injectBodyCSS — port of original demo/main.go injectBodyCSS()
// ---------------------------------------------------------------------------
fn injectBodyCSS() void {
    dom.addNewStyleElement(body_style);
}

// ---------------------------------------------------------------------------
// createAppElements — port of original demo/main.go createAppElements()
// ---------------------------------------------------------------------------
fn createAppElements() void {
    article_element = dom.createElement("article");
    aside_element = dom.createElement("aside");

    dom.addElementTo(application_container, article_element);
    dom.addElementTo(application_container, aside_element);
}

// ---------------------------------------------------------------------------
// populateArticleElement — port of original demo/main.go populateArticleElement()
// ---------------------------------------------------------------------------
fn populateArticleElement() void {
    const p = dom.createParagraphWithText(dommie_text);
    dom.addElementTo(article_element, p);
}

// ---------------------------------------------------------------------------
// Set the title — replaces the JS bootstrap() call from the original.
// The original had JS call getVersion() then set innerHTML. Simpler to
// do it all from Zig since we have the handle.
// ---------------------------------------------------------------------------
fn setTitle() void {
    var buf: [128]u8 = undefined;
    const version_str = std.fmt.bufPrint(&buf, "{s} v{s}", .{ NAME, VERSION }) catch "Zigdom Demo";
    const title_elem = dom.getElementById("title");
    if (title_elem != dom.INVALID) {
        dom.setInnerText(title_elem, version_str);
    }
}

// ---------------------------------------------------------------------------
// zig_init — exported entry point. JS calls this once after WASM instantiation.
// Ports the original demo/main.go main() function.
// ---------------------------------------------------------------------------
export fn zig_init() void {
    // 1. Initialize the DOM module (captures document/body/head handles)
    dom.init();

    // 2. Log startup
    dom.log(&.{ "Ok.", "Zigdom is starting.", "Here we go!" });

    // 3. Toggle visibility
    toggleElements();

    // 4. Set page title
    setTitle();

    // 5. Inject body CSS
    injectBodyCSS();

    // 6. Get application container
    application_container = dom.getElementById("application");

    // 7. Create app elements
    createAppElements();

    // 8. Populate article
    populateArticleElement();

    // 9. Mark ready
    is_ready = true;

    // 10. Register event listeners (using callback IDs 0 and 1)
    dom.addEventListenerById("addSomethingButton", "click", 0);
    dom.addEventListenerById("clearAsideButton", "click", 1);
}
