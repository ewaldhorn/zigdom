const std = @import("std");
const dom = @import("dom.zig");
const colour = @import("colour.zig");
const canvas = @import("canvas.zig");

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
// Canvas memory buffers and globals
// Fully allocation-free in the WASM data segment
var canvas_one_buffer: [800 * 600 * 4]u8 = undefined;
var canvas_two_buffer: [330 * 200 * 4]u8 = undefined;

var canvasOne: canvas.Canvas = undefined;
var canvasTwo: canvas.Canvas = undefined;

var anim_x: i32 = 0;
var anim_y: i32 = 0;
var pixels_per_tick: i32 = 0;

// ---------------------------------------------------------------------------
// Callback dispatch — exported so JS can call into Zig from event listeners.
// The JS side calls zig_invoke_callback(id) when a registered DOM/timer event fires.
// ---------------------------------------------------------------------------
export fn zig_invoke_callback(id: u32) void {
    switch (id) {
        0 => onAddSomethingClick(),
        1 => onClearAsideClick(),
        2 => onRefreshCanvasOneClick(),
        3 => onAnimationTick(),
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
fn onRefreshCanvasOneClick() void {
    if (!is_ready) return;
    performDemoOnCanvasOne();
}

// ---------------------------------------------------------------------------
fn onAnimationTick() void {
    if (!is_ready) return;
    updateCanvasTwo();
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
fn toggleElements() void {
    dom.hide("loading");
    dom.show("controls");
    dom.show("information");
}

// ---------------------------------------------------------------------------
fn injectBodyCSS() void {
    dom.addNewStyleElement(body_style);
}

// ---------------------------------------------------------------------------
fn createAppElements() void {
    article_element = dom.createElement("article");
    aside_element = dom.createElement("aside");

    dom.addElementTo(application_container, article_element);
    dom.addElementTo(application_container, aside_element);
}

// ---------------------------------------------------------------------------
fn populateArticleElement() void {
    const p = dom.createParagraphWithText(dommie_text);
    dom.addElementTo(article_element, p);
}

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
// Canvas 1 Drawing Demo
// ---------------------------------------------------------------------------
fn performDemoOnCanvasOne() void {
    const w = @as(i32, @intCast(canvasOne.width));
    const h = @as(i32, @intCast(canvasOne.height));

    // Clear to dark blue
    canvasOne.clearScreen(colour.Colour{ .r = 10, .g = 20, .b = 180, .a = 255 });

    // Draw bright green canvas backdrop rectangle
    canvasOne.colourFilledRectangle(10, 10, w - 20, h - 20, colour.Colour{ .r = 0, .g = 255, .b = 0, .a = 255 });
    
    // Draw lines grid
    drawLines();

    // Draw overlay white boxes
    canvasOne.colourFilledRectangle(10, 10, @divTrunc(w, 2) - 10, @divTrunc(h, 2) - 10, colour.Colour.white);
    canvasOne.colourFilledRectangle(w - 130, h - 130, 120, 120, colour.Colour.white);

    // Draw pixel grid, worm, spirals
    drawWithPixels();
    drawRandomFilledRectangles();
    drawRandomRectangles();
    drawRandomCircles();
    drawSpiral();

    // Render WASM buffer direct to canvas context
    canvasOne.render();

    // Access Canvas Context 2D directly to draw overlapping semi-transparent arcs
    const ctx = canvasOne.getContext2D();
    
    ctx.beginPath();
    ctx.fillStyle("red");
    ctx.arc(@floatFromInt(w - 150), @floatFromInt(@divTrunc(h, 2)), 50.0, 0.0, 2.75, false);
    ctx.fill();

    ctx.beginPath();
    ctx.fillStyle("blue");
    ctx.arc(@floatFromInt(w - 170), @floatFromInt(@divTrunc(h, 2) - 8), 10.0, 0.0, 7.0, false);
    ctx.fill();

    ctx.beginPath();
    ctx.fillStyle("blue");
    ctx.arc(@floatFromInt(w - 140), @floatFromInt(@divTrunc(h, 2) - 15), 10.0, 0.0, 7.0, false);
    ctx.fill();
}

fn drawWithPixels() void {
    const redPixel = colour.Colour{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const gridSize: i32 = 50;
    const w = @as(i32, @intCast(canvasOne.width));
    const h = @as(i32, @intCast(canvasOne.height));
    
    var x: i32 = 0;
    while (x < gridSize) : (x += 5) {
        var y: i32 = 0;
        while (y < gridSize) : (y += 5) {
            canvasOne.colourPutPixel(@divTrunc(w, 2) - gridSize + x, @divTrunc(h, 2) - gridSize + y, redPixel);
        }
    }
}

fn drawRandomFilledRectangles() void {
    const h = @as(i32, @intCast(canvasOne.height));
    
    // down the left bottom side
    var i: u8 = 0;
    while (i < 15) : (i += 1) {
        const i_i32 = @as(i32, @intCast(i));
        canvasOne.setColour(colour.Colour{ .r = i * 3, .g = 40 + i * 14, .b = 40 + i * 18, .a = 255 });
        canvasOne.filledRectangle(15, 10 + @divTrunc(h, 2) + i_i32 * 17, 15, 15);
    }

    var rx: i32 = 0;
    while (rx < 40) : (rx += 1) {
        var ry: i32 = 0;
        while (ry < 40) : (ry += 1) {
            canvasOne.colourFilledRectangle(20 + (rx * 4), 20 + (ry * 4), 20, 20, colour.NewRandomColour());
        }
    }
}

fn drawRandomRectangles() void {
    const w = @as(i32, @intCast(canvasOne.width));
    var y: i32 = 0;
    while (y < 4) : (y += 1) {
        var i: i32 = 0;
        while (i < 10) : (i += 1) {
            canvasOne.colourRectangle(10 + @divTrunc(w, 2) + (i * 15), 20 + (20 * y), 10, 10, 1, colour.NewRandomColour());
        }
    }
}

fn drawRandomCircles() void {
    const w = @as(i32, @intCast(canvasOne.width));
    const h = @as(i32, @intCast(canvasOne.height));

    // colour worm
    var i: i32 = 0;
    while (i < 24) : (i += 1) {
        canvasOne.colourFilledCircle((i * 4) + 50 + @divTrunc(w, 4), 60, 40, colour.Colour{ .r = @as(u8, @intCast(64 + i * 8)), .g = 64, .b = 255, .a = 255 });
    }

    // increasing thickness borders
    canvasOne.setColour(colour.Colour{ .r = 64, .g = 64, .b = 255, .a = 255 });
    i = 0;
    while (i < 5) : (i += 1) {
        canvasOne.borderCircle(100 + @divTrunc(w, 4), @divTrunc(h, 4), 20 + (i * 6), i + 1);
    }

    // random colour circles
    i = 6;
    while (i < 60) : (i += 3) {
        canvasOne.colourCircle(w - 70, h - 70, i, colour.NewRandomColour());
    }
}

fn drawLines() void {
    canvasOne.setColour(colour.Colour{ .r = 255, .g = 0, .b = 0, .a = 255 });
    const w = @as(i32, @intCast(canvasOne.width));
    const h = @as(i32, @intCast(canvasOne.height));
    
    canvasOne.linePoint(canvas.Point{ .x = 0, .y = 0 }, canvas.Point{ .x = w, .y = h }); // top left to bottom right
    canvasOne.line(@divTrunc(w, 2), @divTrunc(h, 2), w, 0); // middle to top right

    canvasOne.setColour(colour.Colour.black);

    var i: i32 = 0;
    while (i < 60) : (i += 5) {
        canvasOne.line(40, 10 + @divTrunc(h, 2) + i, @divTrunc(w, 2) - i - 40, 10 + @divTrunc(h, 2) + i); // top
        canvasOne.line(40 + i, 10 + @divTrunc(h, 2) + i, 40 + i, h - 20 - i); // left
        canvasOne.line(@divTrunc(w, 2) - i - 40, 10 + @divTrunc(h, 2) + i, @divTrunc(w, 2) - i - 40, h - 20 - i); // right
        canvasOne.line(40, h - i - 20, @divTrunc(w, 2) - i - 40, h - i - 20); // bottom
    }
}

fn drawSpiral() void {
    canvasOne.setColour(colour.Colour.black);
    const w = @as(i32, @intCast(canvasOne.width));
    const h = @as(i32, @intCast(canvasOne.height));
    var centerX = @divTrunc(w, 4);
    var centerY = @divTrunc(h, 2) + @divTrunc(h, 4);

    // Initial direction (0: east, 1: south, 2: west, 3: north)
    var direction: i32 = 0;

    // Number of steps to take in each direction
    var steps: i32 = 1;

    // Number of times to change direction
    const targetSize: i32 = 32;

    const stepSize: i32 = 2;

    // Current number of changes
    var currentSize: i32 = 0;

    // Previous position
    var prevX = centerX;
    var prevY = centerY;

    while (currentSize < targetSize) {
        // Take steps in the current direction
        var i: i32 = 0;
        while (i < steps * 2) : (i += 1) {
            // Store the current position as the previous position
            prevX = centerX;
            prevY = centerY;

            // Move in the current direction
            switch (direction) {
                0 => centerX += stepSize, // east
                1 => centerY -= stepSize, // south
                2 => centerX -= stepSize, // west
                3 => centerY += stepSize, // north
                else => {},
            }

            // Draw a line from the previous position to the current position
            canvasOne.line(prevX, prevY, centerX, centerY);
        }

        // Change direction
        direction = @mod(direction + 1, 4);

        // Increase the number of steps for the next direction
        steps += 1;

        // Increment the change counter
        currentSize += 1;
    }
}

// ---------------------------------------------------------------------------
// Canvas 2 Animation Demo
// ---------------------------------------------------------------------------
fn updateCanvasTwo() void {
    canvasTwo.setColour(colour.NewRandomColour());

    var i: i32 = 0;
    while (i < pixels_per_tick) : (i += 1) {
        anim_x += 1;

        if (anim_x >= @as(i32, @intCast(canvasTwo.width))) {
            anim_x = 1;
            anim_y += 1;
        }

        if (anim_y >= @as(i32, @intCast(canvasTwo.height))) {
            anim_y = 1;
            pixels_per_tick = @as(i32, @intCast(canvasTwo.width)) * @as(i32, @intCast(nextRandom() % 14 + 1));
        }

        canvasTwo.putPixel(anim_x, anim_y);
    }

    renderTriangle();
    canvasTwo.render();
}

fn renderTriangle() void {
    canvasTwo.setColour(colour.Colour.white);

    const w = @as(i32, @intCast(canvasTwo.width));
    const h = @as(i32, @intCast(canvasTwo.height));

    var i: i32 = 0;
    while (i < 40) : (i += 2) {
        canvasTwo.triangle(
            canvas.Point{ .x = @divTrunc(w, 2), .y = @divTrunc(h, 3) + i },
            canvas.Point{ .x = (w - @divTrunc(w, 3)) + i, .y = (h - @divTrunc(h, 3)) - i },
            canvas.Point{ .x = @divTrunc(w, 3) - i, .y = (h - @divTrunc(h, 3)) - i },
        );
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

    // 9. Register DOM event listeners
    dom.addEventListenerById("addSomethingButton", "click", 0);
    dom.addEventListenerById("clearAsideButton", "click", 1);
    dom.addEventListenerById("refreshButton", "click", 2);

    // 10. Instantiate the ported Canvases
    // Direct zero-copy mapping into statically allocated WASM global buffers
    canvasOne = canvas.Canvas.init(800, 600, &canvas_one_buffer, "tinyCanvasDiv");
    canvasTwo = canvas.Canvas.init(330, 200, &canvas_two_buffer, "tinyCanvasDiv");

    // 11. Run static canvasOne graphics demo
    performDemoOnCanvasOne();

    // 12. Setup animated canvasTwo graphics demo
    colour.seed(42);
    pixels_per_tick = @as(i32, @intCast(canvasTwo.width)) * 2;
    anim_x = 0;
    anim_y = 0;
    canvasTwo.clearScreen(colour.Colour{ .r = 80, .g = 80, .b = 180, .a = 255 });

    // 13. Mark ready
    is_ready = true;

    // 14. Start high-performance browser tick rendering cycle driven by requestAnimationFrame
    dom.startAnimationLoop(3);
}
