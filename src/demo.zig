const std = @import("std");
const dom = @import("dom.zig");
const colour = @import("colour.zig");
const canvas = @import("canvas.zig");

// ------------------------------------------------------------------------------------------------
// Resources & Constants
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
const body_style = @embedFile("bodystyle.css");
const dommie_text = @embedFile("zigdom.txt");
const VERSION = "0.0.1a";
const NAME = "Zigdom Demo";

// ------------------------------------------------------------------------------------------------
// Application State
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
var is_ready: bool = false;
var boo_counter: u32 = 0;
var application_container: dom.Handle = dom.INVALID;
var article_element: dom.Handle = dom.INVALID;
var aside_element: dom.Handle = dom.INVALID;

// ------------------------------------------------------------------------------------------------
// CSS class / size options for addRandomParagraph
const css_colours = [_][]const u8{ "red", "blue", "orange" };
const css_sizes = [_][]const u8{ "large", "larger", "xlarge" };

// ------------------------------------------------------------------------------------------------
// Demo-local PRNG (xorshift64*) — independent of colour.zig's PRNG.
// Used for UI randomisation and to cross-seed colour.zig before each canvas
// redraw via `colour.seed(nextRandom())`, ensuring each refresh looks unique.
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
var rng_state: u64 = 42;

// ------------------------------------------------------------------------------------------------
fn nextRandom() u32 {
    rng_state ^= rng_state << 13;
    rng_state ^= rng_state >> 7;
    rng_state ^= rng_state << 17;
    return @truncate(rng_state);
}

// ------------------------------------------------------------------------------------------------
fn randomCssColour() []const u8 {
    return css_colours[nextRandom() % css_colours.len];
}

// ------------------------------------------------------------------------------------------------
fn randomCssSize() []const u8 {
    return css_sizes[nextRandom() % css_sizes.len];
}

// ------------------------------------------------------------------------------------------------
// Canvas buffers — zero-heap, allocated in WASM data segment.
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
// Canvas One: 800×600 static synthwave gallery
var canvas_one_buffer: [800 * 600 * 4]u8 = undefined;
var canvasOne: canvas.Canvas = undefined;

// ------------------------------------------------------------------------------------------------
// Canvas Two: 600×450 animated ball-physics simulation
var canvas_two_buffer: [600 * 450 * 4]u8 = undefined;
var canvasTwo: canvas.Canvas = undefined;

// ------------------------------------------------------------------------------------------------
// Ball physics — fixed-size array, no heap.
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
const MAX_BALLS = 14;

// ------------------------------------------------------------------------------------------------
const Ball = struct {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    /// Stored as f32 to avoid casts in the physics hot path.
    radius: f32,
    col: colour.Colour,
};

// ------------------------------------------------------------------------------------------------
var balls: [MAX_BALLS]Ball = undefined;

// ------------------------------------------------------------------------------------------------
// Interaction coordinates — written by JS before invoking callback 4.
// Reset to -1 after each impulse so spurious re-fires are no-ops.
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
var interact_x: i32 = -1;
var interact_y: i32 = -1;

// ------------------------------------------------------------------------------------------------
/// Called by JS to pass the click/touch canvas-pixel coordinates to Zig
/// before firing callback 4 (`onCanvasInteraction`).
export fn zig_set_interaction(x: i32, y: i32) void {
    interact_x = x;
    interact_y = y;
}

// ------------------------------------------------------------------------------------------------
// Callback dispatch
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
/// JS calls this from DOM event listeners and the rAF animation loop.
export fn zig_invoke_callback(id: u32) void {
    switch (id) {
        0 => onAddSomethingClick(),
        1 => onClearAsideClick(),
        2 => onRefreshCanvasOneClick(),
        3 => onAnimationTick(),
        4 => onCanvasInteraction(),
        else => {},
    }
}

// ------------------------------------------------------------------------------------------------
fn onAddSomethingClick() void {
    if (!is_ready) return;
    if (nextRandom() % 2 == 0) addBoo() else addRandomParagraph();
}

// ------------------------------------------------------------------------------------------------
fn onClearAsideClick() void {
    if (!is_ready) return;
    dom.removeAllChildElementsFrom(aside_element);
}

// ------------------------------------------------------------------------------------------------
fn onRefreshCanvasOneClick() void {
    if (!is_ready) return;
    performDemoOnCanvasOne();
}

// ------------------------------------------------------------------------------------------------
fn onAnimationTick() void {
    if (!is_ready) return;
    updateCanvasTwo();
}

// ------------------------------------------------------------------------------------------------
/// Applies an outward velocity impulse to every ball, away from the tap point.
/// The interaction coordinates are reset afterwards so re-fires are harmless.
fn onCanvasInteraction() void {
    if (!is_ready) return;
    if (interact_x < 0 or interact_y < 0) return;
    defer {
        interact_x = -1;
        interact_y = -1;
    }

    const ix: f32 = @floatFromInt(interact_x);
    const iy: f32 = @floatFromInt(interact_y);

    for (&balls) |*ball| {
        const dx = ball.x - ix;
        const dy = ball.y - iy;
        const dist_sq = dx * dx + dy * dy;
        if (dist_sq < 1.0) continue;
        const dist = @sqrt(dist_sq);
        const impulse = @min(180.0 / dist, 12.0); // inverse-distance, capped
        ball.vx += (dx / dist) * impulse;
        ball.vy += (dy / dist) * impulse;
    }
}

// ------------------------------------------------------------------------------------------------
// DOM helpers
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
fn addBoo() void {
    boo_counter += 1;
    var buf: [32]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "Boo! ({d})", .{boo_counter}) catch "Boo!";
    dom.addElementTo(aside_element, dom.createParagraphWithText(text));
}

// ------------------------------------------------------------------------------------------------
fn addRandomParagraph() void {
    const p = dom.createParagraphWithText("This is some text");
    const wrapped = dom.wrapElementWithNewDiv(p, &.{ randomCssColour(), randomCssSize() });
    dom.addElementTo(aside_element, wrapped);
}

// ------------------------------------------------------------------------------------------------
fn toggleElements() void {
    dom.hide("loading");
    dom.show("controls");
    dom.show("information");
}

// ------------------------------------------------------------------------------------------------
fn createAppElements() void {
    article_element = dom.createElement("article");
    aside_element = dom.createElement("aside");
    dom.addElementTo(application_container, article_element);
    dom.addElementTo(application_container, aside_element);
}

// ------------------------------------------------------------------------------------------------
fn populateArticleElement() void {
    dom.addElementTo(article_element, dom.createParagraphWithText(dommie_text));
}

// ------------------------------------------------------------------------------------------------
fn setTitle() void {
    var buf: [128]u8 = undefined;
    const title = std.fmt.bufPrint(&buf, "{s} v{s}", .{ NAME, VERSION }) catch "Zigdom Demo";
    const elem = dom.getElementById("title");
    if (elem != dom.INVALID) dom.setInnerText(elem, title);
}

// ------------------------------------------------------------------------------------------------
// CANVAS ONE — Dark Synthwave Gallery (800×600, static)
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
// Palette — all neon on near-black.
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
const sw_bg = colour.Colour{ .r = 5, .g = 5, .b = 16, .a = 255 };
const sw_panel = colour.Colour{ .r = 12, .g = 12, .b = 36, .a = 255 };
const sw_cyan = colour.Colour{ .r = 0, .g = 240, .b = 220, .a = 255 };
const sw_magenta = colour.Colour{ .r = 255, .g = 0, .b = 180, .a = 255 };
const sw_yellow = colour.Colour{ .r = 255, .g = 230, .b = 0, .a = 255 };
const sw_gold = colour.Colour{ .r = 255, .g = 180, .b = 30, .a = 255 };
const sw_violet = colour.Colour{ .r = 160, .g = 0, .b = 255, .a = 255 };

// ------------------------------------------------------------------------------------------------
fn performDemoOnCanvasOne() void {
    const w: i32 = @intCast(canvasOne.width);
    const h: i32 = @intCast(canvasOne.height);

    // Cross-seed colour PRNG from the demo PRNG so each refresh looks different.
    colour.seed(@as(u64, nextRandom()) | 1);

    canvasOne.clearScreen(sw_bg);
    canvasOne.colourRectangle(8, 8, w - 16, h - 16, 2, sw_panel);

    drawSynthwaveLines(w, h);

    // Overlay panel outlines
    canvasOne.colourRectangle(10, 10, @divTrunc(w, 2) - 14, @divTrunc(h, 2) - 14, 1, sw_violet);
    canvasOne.colourRectangle(w - 132, h - 132, 122, 122, 1, sw_cyan);

    drawNeonPixelGrid(w, h);
    drawGradientFilledRectangles(h);
    drawNeonOutlineRectangles(w);
    drawSynthwaveCircles(w, h);
    drawRainbowSpiral(w, h);

    canvasOne.render();

    drawGlowingHalos(canvasOne.getContext2D(), w, h);
}

// ------------------------------------------------------------------------------------------------
fn drawSynthwaveLines(w: i32, h: i32) void {
    canvasOne.colourLine(0, 0, w, h, sw_magenta);
    canvasOne.colourLine(@divTrunc(w, 2), @divTrunc(h, 2), w, 0, sw_cyan);

    // Concentric inset rectangles, alternating cyan / violet
    var i: i32 = 0;
    while (i < 60) : (i += 5) {
        const c = if (@mod(@divTrunc(i, 5), 2) == 0) sw_cyan else sw_violet;
        canvasOne.colourRectangle(
            40 + i,
            10 + @divTrunc(h, 2) + i,
            @divTrunc(w, 2) - i * 2 - 80,
            h - 30 - @divTrunc(h, 2) - i * 2,
            1,
            c,
        );
    }
}

// ------------------------------------------------------------------------------------------------
fn drawNeonPixelGrid(w: i32, h: i32) void {
    const size: i32 = 50;
    var x: i32 = 0;
    while (x < size) : (x += 5) {
        var y: i32 = 0;
        while (y < size) : (y += 5) {
            canvasOne.colourPutPixel(
                @divTrunc(w, 2) - size + x,
                @divTrunc(h, 2) - size + y,
                sw_cyan,
            );
        }
    }
}

// ------------------------------------------------------------------------------------------------
fn drawGradientFilledRectangles(h: i32) void {
    // Column of magenta→violet gradient rects
    var i: u8 = 0;
    while (i < 15) : (i += 1) {
        const step: i32 = @intCast(i);
        canvasOne.colourFilledRectangle(
            15,
            10 + @divTrunc(h, 2) + step * 17,
            15,
            15,
            colour.Colour{ .r = 255 - i * 6, .g = 0, .b = 100 + i * 10, .a = 255 },
        );
    }

    // Dense grid of random neon rects — different every refresh
    var rx: i32 = 0;
    while (rx < 40) : (rx += 1) {
        var ry: i32 = 0;
        while (ry < 40) : (ry += 1) {
            canvasOne.colourFilledRectangle(20 + rx * 4, 20 + ry * 4, 20, 20, colour.randomColour());
        }
    }
}

// ------------------------------------------------------------------------------------------------
fn drawNeonOutlineRectangles(w: i32) void {
    var row: i32 = 0;
    while (row < 4) : (row += 1) {
        var col: i32 = 0;
        while (col < 10) : (col += 1) {
            canvasOne.colourRectangle(
                10 + @divTrunc(w, 2) + col * 15,
                20 + 20 * row,
                10,
                10,
                1,
                sw_yellow,
            );
        }
    }
}

// ------------------------------------------------------------------------------------------------
fn drawSynthwaveCircles(w: i32, h: i32) void {
    // Worm of filled circles — random neon each refresh
    var i: i32 = 0;
    while (i < 24) : (i += 1) {
        canvasOne.colourFilledCircle(i * 4 + 50 + @divTrunc(w, 4), 60, 40, colour.randomColour());
    }

    // Concentric border rings — random colour each refresh
    i = 0;
    while (i < 5) : (i += 1) {
        canvasOne.colourBorderCircle(
            100 + @divTrunc(w, 4),
            @divTrunc(h, 4),
            20 + i * 6,
            i + 1,
            colour.randomColour(),
        );
    }

    // Target rings — random colours each refresh
    i = 6;
    while (i < 60) : (i += 3) {
        canvasOne.colourCircle(w - 70, h - 70, i, colour.randomColour());
    }
}

// ------------------------------------------------------------------------------------------------
fn drawRainbowSpiral(w: i32, h: i32) void {
    var cx = @divTrunc(w, 4);
    var cy = @divTrunc(h, 2) + @divTrunc(h, 4);
    var px = cx;
    var py = cy;
    var direction: i32 = 0; // 0=east 1=south 2=west 3=north
    var steps: i32 = 1;
    var hue: u32 = 0;

    var turn: i32 = 0;
    while (turn < 32) : (turn += 1) {
        var step: i32 = 0;
        while (step < steps * 2) : (step += 1) {
            px = cx;
            py = cy;
            switch (direction) {
                0 => cx += 2,
                1 => cy -= 2,
                2 => cx -= 2,
                3 => cy += 2,
                else => {},
            }
            canvasOne.colourLine(px, py, cx, cy, rainbowColour(hue));
            hue +%= 1;
        }
        direction = @mod(direction + 1, 4);
        steps += 1;
    }
}

// ------------------------------------------------------------------------------------------------
/// Maps a wrapping index to a smooth 6-segment rainbow colour.
/// Each segment covers ~43 steps giving a full cycle per 256 indices.
fn rainbowColour(idx: u32) colour.Colour {
    const t: u8 = @truncate(idx); // implicit mod 256
    const section = t / 43;
    const prog = t % 43;
    // prog * 6 ≤ 42 * 6 = 252, safe to @truncate to u8
    const p: u8 = @truncate(@as(u32, prog) * 6);
    return switch (section) {
        0 => .{ .r = 255, .g = p, .b = 0, .a = 255 }, // red→yellow
        1 => .{ .r = 255 - p, .g = 255, .b = 0, .a = 255 }, // yellow→green
        2 => .{ .r = 0, .g = 255, .b = p, .a = 255 }, // green→cyan
        3 => .{ .r = 0, .g = 255 - p, .b = 255, .a = 255 }, // cyan→blue
        4 => .{ .r = p, .g = 0, .b = 255, .a = 255 }, // blue→magenta
        else => .{ .r = 255, .g = 0, .b = 255 - p, .a = 255 }, // magenta→red
    };
}

// ------------------------------------------------------------------------------------------------
fn drawGlowingHalos(ctx: dom.Context2D, w: i32, h: i32) void {
    const cx: f64 = @floatFromInt(w - 100);
    const cy: f64 = @floatFromInt(@divTrunc(h, 2));

    ctx.beginPath();
    ctx.fillStyle("rgba(255,0,180,0.18)");
    ctx.arc(cx, cy, 70.0, 0.0, 6.2832, false);
    ctx.fill();
    ctx.beginPath();
    ctx.fillStyle("rgba(0,240,220,0.28)");
    ctx.arc(cx, cy, 48.0, 0.0, 6.2832, false);
    ctx.fill();
    ctx.beginPath();
    ctx.fillStyle("rgba(255,180,30,0.55)");
    ctx.arc(cx, cy, 26.0, 0.0, 6.2832, false);
    ctx.fill();
    ctx.beginPath();
    ctx.fillStyle("rgba(255,60,200,0.90)");
    ctx.arc(cx, cy, 10.0, 0.0, 6.2832, false);
    ctx.fill();
}

// ------------------------------------------------------------------------------------------------
// CANVAS TWO — Ball Physics Simulation (600×450, animated)
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
fn initBalls() void {
    const w: f32 = @floatFromInt(canvasTwo.width);
    const h: f32 = @floatFromInt(canvasTwo.height);

    // Each row: x%, y%, vx*100, vy*100, radius
    const init_data = [MAX_BALLS][5]i32{
        .{ 20, 30, 270, -180, 12 },
        .{ 70, 20, -300, 120, 14 },
        .{ 50, 60, 180, 300, 11 },
        .{ 15, 70, -135, -270, 13 },
        .{ 80, 75, 330, -90, 9 },
        .{ 40, 40, -225, -225, 16 },
        .{ 60, 80, 150, 375, 12 },
        .{ 30, 15, -375, 150, 10 },
        .{ 85, 45, -165, -300, 17 },
        .{ 10, 50, 450, 135, 9 },
        .{ 55, 25, -270, -120, 13 },
        .{ 75, 60, 120, -330, 15 },
        .{ 25, 85, 300, 90, 11 },
        .{ 90, 10, -195, 255, 12 },
    };

    const ball_colours = [MAX_BALLS]colour.Colour{
        .{ .r = 0, .g = 240, .b = 220, .a = 255 }, // cyan
        .{ .r = 255, .g = 0, .b = 180, .a = 255 }, // magenta
        .{ .r = 0, .g = 255, .b = 100, .a = 255 }, // green
        .{ .r = 255, .g = 230, .b = 0, .a = 255 }, // yellow
        .{ .r = 160, .g = 0, .b = 255, .a = 255 }, // violet
        .{ .r = 255, .g = 100, .b = 0, .a = 255 }, // orange
        .{ .r = 0, .g = 160, .b = 255, .a = 255 }, // sky blue
        .{ .r = 255, .g = 0, .b = 80, .a = 255 }, // hot red
        .{ .r = 100, .g = 255, .b = 200, .a = 255 }, // mint
        .{ .r = 255, .g = 160, .b = 0, .a = 255 }, // amber
        .{ .r = 200, .g = 0, .b = 255, .a = 255 }, // purple
        .{ .r = 0, .g = 255, .b = 255, .a = 255 }, // electric cyan
        .{ .r = 255, .g = 80, .b = 180, .a = 255 }, // pink
        .{ .r = 80, .g = 255, .b = 0, .a = 255 }, // lime
    };

    for (0..MAX_BALLS) |i| {
        const d = init_data[i];
        balls[i] = .{
            .x = w * @as(f32, @floatFromInt(d[0])) / 100.0,
            .y = h * @as(f32, @floatFromInt(d[1])) / 100.0,
            .vx = @as(f32, @floatFromInt(d[2])) / 100.0,
            .vy = @as(f32, @floatFromInt(d[3])) / 100.0,
            .radius = @floatFromInt(d[4]),
            .col = ball_colours[i],
        };
    }
}

// ------------------------------------------------------------------------------------------------
fn updateCanvasTwo() void {
    const w: f32 = @floatFromInt(canvasTwo.width);
    const h: f32 = @floatFromInt(canvasTwo.height);
    const gravity: f32 = 0.08;
    const dampen: f32 = 0.88;
    const bg = colour.Colour{ .r = 8, .g = 8, .b = 15, .a = 255 };

    canvasTwo.clearScreen(bg);

    for (&balls) |*ball| {
        ball.vy += gravity;
        ball.x += ball.vx;
        ball.y += ball.vy;

        const r = ball.radius;

        if (ball.x - r < 0.0) {
            ball.x = r;
            ball.vx = @abs(ball.vx) * dampen;
        }
        if (ball.x + r > w) {
            ball.x = w - r;
            ball.vx = -@abs(ball.vx) * dampen;
        }
        if (ball.y - r < 0.0) {
            ball.y = r;
            ball.vy = @abs(ball.vy) * dampen;
        }
        if (ball.y + r > h) {
            ball.y = h - r;
            ball.vy = -@abs(ball.vy) * dampen;
        }

        const bx: i32 = @intFromFloat(ball.x);
        const by: i32 = @intFromFloat(ball.y);
        const br: i32 = @intFromFloat(r);

        // Dim glow halo — floor each channel at 20 so zero-channel balls still glow
        const glow = colour.Colour{
            .r = @max(ball.col.r / 3, 20),
            .g = @max(ball.col.g / 3, 20),
            .b = @max(ball.col.b / 3, 20),
            .a = 255,
        };
        canvasTwo.colourFilledCircle(bx, by, br + 4, glow);
        canvasTwo.colourFilledCircle(bx, by, br, ball.col);

        // Specular highlight
        const hs: i32 = @intFromFloat(r / 3.0);
        canvasTwo.colourPutPixel(bx - hs, by - hs, colour.Colour.white);
    }

    canvasTwo.render();
}

// ------------------------------------------------------------------------------------------------
// Entry point
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
/// Exported entry point — JS calls this once after WASM instantiation.
export fn zig_init() void {
    dom.init();
    dom.log(&.{ "Ok.", "Zigdom is starting.", "Here we go!" });

    toggleElements();
    setTitle();
    dom.addNewStyleElement(body_style);

    application_container = dom.getElementById("application");
    createAppElements();
    populateArticleElement();

    dom.addEventListenerById("addSomethingButton", "click", 0);
    dom.addEventListenerById("clearAsideButton", "click", 1);
    dom.addEventListenerById("refreshButton", "click", 2);

    canvasOne = canvas.Canvas.init(800, 600, &canvas_one_buffer, "canvasOneDiv");
    canvasTwo = canvas.Canvas.init(600, 450, &canvas_two_buffer, "canvasTwoDiv");

    performDemoOnCanvasOne();
    initBalls();

    is_ready = true;

    // Start the rAF loop — callback 3 fires once per browser frame.
    dom.startAnimationLoop(3);
}
