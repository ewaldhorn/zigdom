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
// Canvas One: 800x600 static synthwave gallery
var canvas_one_buffer: [800 * 600 * 4]u8 = undefined;
var canvasOne: canvas.Canvas = undefined;

// ---------------------------------------------------------------------------
// Canvas Two: 400x300 animated physics simulation
var canvas_two_buffer: [600 * 450 * 4]u8 = undefined;
var canvasTwo: canvas.Canvas = undefined;

// ---------------------------------------------------------------------------
// Ball physics globals — no heap, fixed array
const MAX_BALLS = 14;

const Ball = struct {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    radius: i32,
    col: colour.Colour,
};

var balls: [MAX_BALLS]Ball = undefined;

// ---------------------------------------------------------------------------
// Interaction coordinates written by JS before invoking callback 4
var interact_x: i32 = -1;
var interact_y: i32 = -1;

// ---------------------------------------------------------------------------
// Exported so JS can set the interaction point prior to firing callback 4.
export fn zig_set_interaction(x: i32, y: i32) void {
    interact_x = x;
    interact_y = y;
}

// ---------------------------------------------------------------------------
// Callback dispatch — exported so JS can call into Zig from event listeners.
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
// Apply velocity impulse to all balls away from the tap/click point
fn onCanvasInteraction() void {
    if (!is_ready) return;
    if (interact_x < 0 or interact_y < 0) return;

    const ix: f32 = @floatFromInt(interact_x);
    const iy: f32 = @floatFromInt(interact_y);

    for (&balls) |*ball| {
        const dx = ball.x - ix;
        const dy = ball.y - iy;
        const dist_sq = dx * dx + dy * dy;
        if (dist_sq < 1.0) continue;

        // Inverse-distance impulse, capped strength
        const dist = @sqrt(dist_sq);
        const strength: f32 = 180.0 / dist;
        const capped = @min(strength, 12.0);
        ball.vx += (dx / dist) * capped;
        ball.vy += (dy / dist) * capped;
    }
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

// ===========================================================================
// CANVAS ONE — Dark Synthwave Gallery
// Same primitives as before; entirely new colour palette and composition.
// ===========================================================================

// Synthwave palette constants
const sw_bg      = colour.Colour{ .r = 5,   .g = 5,   .b = 16,  .a = 255 }; // near-black indigo
const sw_panel   = colour.Colour{ .r = 12,  .g = 12,  .b = 36,  .a = 255 }; // dark panel
const sw_cyan    = colour.Colour{ .r = 0,   .g = 240, .b = 220, .a = 255 }; // neon cyan
const sw_magenta = colour.Colour{ .r = 255, .g = 0,   .b = 180, .a = 255 }; // neon magenta
const sw_yellow  = colour.Colour{ .r = 255, .g = 230, .b = 0,   .a = 255 }; // neon yellow
const sw_gold    = colour.Colour{ .r = 255, .g = 180, .b = 30,  .a = 255 }; // amber/gold
const sw_green   = colour.Colour{ .r = 0,   .g = 255, .b = 100, .a = 255 }; // neon green
const sw_violet  = colour.Colour{ .r = 160, .g = 0,   .b = 255, .a = 255 }; // electric violet

fn performDemoOnCanvasOne() void {
    const w = @as(i32, @intCast(canvasOne.width));
    const h = @as(i32, @intCast(canvasOne.height));

    // Re-seed the colour PRNG so each refresh looks different
    colour.seed(@as(u64, @intCast(nextRandom())) | 1);

    // 1. Deep indigo background
    canvasOne.clearScreen(sw_bg);

    // 2. Dark panel border outline (replaces the bright green filled rect)
    canvasOne.colourRectangle(8, 8, w - 16, h - 16, 2, sw_panel);

    // 3. Grid lines (replaces the old red/black line grid)
    drawSynthwaveLines();

    // 4. Dark overlay panels (replaces white boxes) — drawn as outline rects
    canvasOne.colourRectangle(10, 10, @divTrunc(w, 2) - 14, @divTrunc(h, 2) - 14, 1, sw_violet);
    canvasOne.colourRectangle(w - 132, h - 132, 122, 122, 1, sw_cyan);

    // 5. Neon cyan pixel grid (replaces plain red dots)
    drawNeonPixelGrid();

    // 6. Hot-pink → violet gradient filled rectangles
    drawGradientFilledRectangles();

    // 7. Neon yellow outline rectangles
    drawNeonOutlineRectangles();

    // 8. Green→cyan gradient worm of filled circles + gold concentric rings
    drawSynthwaveCircles();

    // 9. Rainbow spiral
    drawRainbowSpiral();

    // 10. Blit pixel buffer to browser canvas
    canvasOne.render();

    // 11. Canvas 2D context: glowing neon halos (replaces the plain arcs)
    const ctx = canvasOne.getContext2D();
    drawGlowingHalos(ctx, w, h);
}

fn drawSynthwaveLines() void {
    const w = @as(i32, @intCast(canvasOne.width));
    const h = @as(i32, @intCast(canvasOne.height));

    // Diagonal cross — magenta
    canvasOne.colourLine(0, 0, w, h, sw_magenta);
    canvasOne.colourLine(@divTrunc(w, 2), @divTrunc(h, 2), w, 0, sw_cyan);

    // Concentric inset rectangles (replaces the black line grid)
    var i: i32 = 0;
    while (i < 60) : (i += 5) {
        // Alternate cyan / violet
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

fn drawNeonPixelGrid() void {
    const gridSize: i32 = 50;
    const w = @as(i32, @intCast(canvasOne.width));
    const h = @as(i32, @intCast(canvasOne.height));

    var x: i32 = 0;
    while (x < gridSize) : (x += 5) {
        var y: i32 = 0;
        while (y < gridSize) : (y += 5) {
            canvasOne.colourPutPixel(
                @divTrunc(w, 2) - gridSize + x,
                @divTrunc(h, 2) - gridSize + y,
                sw_cyan,
            );
        }
    }
}

fn drawGradientFilledRectangles() void {
    const h = @as(i32, @intCast(canvasOne.height));

    // Column of gradient rects on the left (hot-pink → violet)
    var i: u8 = 0;
    while (i < 15) : (i += 1) {
        const i_i32 = @as(i32, @intCast(i));
        // Interpolate magenta → violet across 15 steps
        const r: u8 = 255 - i * 6;
        const g: u8 = 0;
        const b: u8 = 100 + i * 10;
        canvasOne.colourFilledRectangle(15, 10 + @divTrunc(h, 2) + i_i32 * 17, 15, 15, colour.Colour{ .r = r, .g = g, .b = b, .a = 255 });
    }

    // Dense grid of random neon filled rects — different every refresh
    var rx: i32 = 0;
    while (rx < 40) : (rx += 1) {
        var ry: i32 = 0;
        while (ry < 40) : (ry += 1) {
            canvasOne.colourFilledRectangle(
                20 + (rx * 4),
                20 + (ry * 4),
                20, 20,
                colour.NewRandomColour(),
            );
        }
    }
}

fn drawNeonOutlineRectangles() void {
    const w = @as(i32, @intCast(canvasOne.width));
    var y: i32 = 0;
    while (y < 4) : (y += 1) {
        var i: i32 = 0;
        while (i < 10) : (i += 1) {
            canvasOne.colourRectangle(
                10 + @divTrunc(w, 2) + (i * 15),
                20 + (20 * y),
                10, 10, 1,
                sw_yellow,
            );
        }
    }
}

fn drawSynthwaveCircles() void {
    const w = @as(i32, @intCast(canvasOne.width));
    const h = @as(i32, @intCast(canvasOne.height));

    // Worm of filled circles — random neon colours, different every refresh
    var i: i32 = 0;
    while (i < 24) : (i += 1) {
        canvasOne.colourFilledCircle(
            (i * 4) + 50 + @divTrunc(w, 4), 60, 40,
            colour.NewRandomColour(),
        );
    }

    // Concentric ring borders — random colour per ring
    i = 0;
    while (i < 5) : (i += 1) {
        canvasOne.colourBorderCircle(100 + @divTrunc(w, 4), @divTrunc(h, 4), 20 + (i * 6), i + 1, colour.NewRandomColour());
    }

    // Target rings — random colours, different every refresh
    i = 6;
    while (i < 60) : (i += 3) {
        canvasOne.colourCircle(w - 70, h - 70, i, colour.NewRandomColour());
    }
}

fn drawRainbowSpiral() void {
    const w = @as(i32, @intCast(canvasOne.width));
    const h = @as(i32, @intCast(canvasOne.height));
    var centerX = @divTrunc(w, 4);
    var centerY = @divTrunc(h, 2) + @divTrunc(h, 4);

    var direction: i32 = 0;
    var steps: i32 = 1;
    const targetSize: i32 = 32;
    const stepSize: i32 = 2;
    var currentSize: i32 = 0;
    var prevX = centerX;
    var prevY = centerY;

    // Colour index cycles through rainbow palette
    var hue_idx: u32 = 0;

    while (currentSize < targetSize) {
        var i: i32 = 0;
        while (i < steps * 2) : (i += 1) {
            prevX = centerX;
            prevY = centerY;

            switch (direction) {
                0 => centerX += stepSize,
                1 => centerY -= stepSize,
                2 => centerX -= stepSize,
                3 => centerY += stepSize,
                else => {},
            }

            // Cycle through rainbow
            const spiral_col = rainbowColour(hue_idx);
            hue_idx +%= 1;
            canvasOne.colourLine(prevX, prevY, centerX, centerY, spiral_col);
        }

        direction = @mod(direction + 1, 4);
        steps += 1;
        currentSize += 1;
    }
}

/// Maps a 0–255 index to a rainbow colour (red→yellow→green→cyan→blue→magenta→red)
fn rainbowColour(idx: u32) colour.Colour {
    const t = @as(u8, @truncate(idx % 256));
    const section = t / 43; // 6 sections of ~43 steps each
    const progress = t % 43;
    const p = @as(u8, @intCast(progress * 6)); // 0..252

    return switch (section) {
        0 => colour.Colour{ .r = 255,       .g = p,         .b = 0,         .a = 255 }, // red→yellow
        1 => colour.Colour{ .r = 255 - p,   .g = 255,       .b = 0,         .a = 255 }, // yellow→green
        2 => colour.Colour{ .r = 0,         .g = 255,       .b = p,         .a = 255 }, // green→cyan
        3 => colour.Colour{ .r = 0,         .g = 255 - p,   .b = 255,       .a = 255 }, // cyan→blue
        4 => colour.Colour{ .r = p,         .g = 0,         .b = 255,       .a = 255 }, // blue→magenta
        else => colour.Colour{ .r = 255,    .g = 0,         .b = 255 - p,   .a = 255 }, // magenta→red
    };
}

fn drawGlowingHalos(ctx: dom.Context2D, w: i32, h: i32) void {
    // Replace the old 3 plain arcs with layered glowing rings
    const cx: f64 = @floatFromInt(w - 100);
    const cy: f64 = @floatFromInt(@divTrunc(h, 2));

    // Outer magenta glow ring
    ctx.beginPath();
    ctx.fillStyle("rgba(255,0,180,0.18)");
    ctx.arc(cx, cy, 70.0, 0.0, 6.2832, false);
    ctx.fill();

    // Mid cyan ring
    ctx.beginPath();
    ctx.fillStyle("rgba(0,240,220,0.28)");
    ctx.arc(cx, cy, 48.0, 0.0, 6.2832, false);
    ctx.fill();

    // Inner gold core
    ctx.beginPath();
    ctx.fillStyle("rgba(255,180,30,0.55)");
    ctx.arc(cx, cy, 26.0, 0.0, 6.2832, false);
    ctx.fill();

    // Hot-pink bright centre
    ctx.beginPath();
    ctx.fillStyle("rgba(255,60,200,0.90)");
    ctx.arc(cx, cy, 10.0, 0.0, 6.2832, false);
    ctx.fill();
}

// ===========================================================================
// CANVAS TWO — Ball Physics Simulation (400×300)
// ===========================================================================

fn initBalls() void {
    // Seed colours and starting positions deterministically
    const w: f32 = @floatFromInt(canvasTwo.width);
    const h: f32 = @floatFromInt(canvasTwo.height);

    const init_data = [MAX_BALLS][5]i32{
        // x%,  y%,  vx*100, vy*100, radius
        .{ 20,  30,  270,  -180,  12 },
        .{ 70,  20, -300,   120,  14 },
        .{ 50,  60,  180,   300,  11 },
        .{ 15,  70, -135,  -270,  13 },
        .{ 80,  75,  330,   -90,   9 },
        .{ 40,  40, -225,  -225,  16 },
        .{ 60,  80,  150,   375,  12 },
        .{ 30,  15, -375,   150,  10 },
        .{ 85,  45, -165,  -300,  17 },
        .{ 10,  50,  450,   135,   9 },
        .{ 55,  25, -270,  -120,  13 },
        .{ 75,  60,  120,  -330,  15 },
        .{ 25,  85,  300,    90,  11 },
        .{ 90,  10, -195,   255,  12 },
    };

    const ball_colours = [MAX_BALLS]colour.Colour{
        colour.Colour{ .r = 0,   .g = 240, .b = 220, .a = 255 }, // cyan
        colour.Colour{ .r = 255, .g = 0,   .b = 180, .a = 255 }, // magenta
        colour.Colour{ .r = 0,   .g = 255, .b = 100, .a = 255 }, // green
        colour.Colour{ .r = 255, .g = 230, .b = 0,   .a = 255 }, // yellow
        colour.Colour{ .r = 160, .g = 0,   .b = 255, .a = 255 }, // violet
        colour.Colour{ .r = 255, .g = 100, .b = 0,   .a = 255 }, // orange
        colour.Colour{ .r = 0,   .g = 160, .b = 255, .a = 255 }, // sky blue
        colour.Colour{ .r = 255, .g = 0,   .b = 80,  .a = 255 }, // hot red
        colour.Colour{ .r = 100, .g = 255, .b = 200, .a = 255 }, // mint
        colour.Colour{ .r = 255, .g = 160, .b = 0,   .a = 255 }, // amber
        colour.Colour{ .r = 200, .g = 0,   .b = 255, .a = 255 }, // purple
        colour.Colour{ .r = 0,   .g = 255, .b = 255, .a = 255 }, // electric blue
        colour.Colour{ .r = 255, .g = 80,  .b = 180, .a = 255 }, // pink
        colour.Colour{ .r = 80,  .g = 255, .b = 0,   .a = 255 }, // lime
    };

    for (0..MAX_BALLS) |i| {
        const d = init_data[i];
        balls[i] = Ball{
            .x      = w * @as(f32, @floatFromInt(d[0])) / 100.0,
            .y      = h * @as(f32, @floatFromInt(d[1])) / 100.0,
            .vx     = @as(f32, @floatFromInt(d[2])) / 100.0,
            .vy     = @as(f32, @floatFromInt(d[3])) / 100.0,
            .radius = d[4],
            .col    = ball_colours[i],
        };
    }
}

fn updateCanvasTwo() void {
    const w: f32 = @floatFromInt(canvasTwo.width);
    const h: f32 = @floatFromInt(canvasTwo.height);
    const gravity: f32 = 0.08;
    const dampen: f32 = 0.88;

    // Clear to near-black each frame
    canvasTwo.clearScreen(colour.Colour{ .r = 8, .g = 8, .b = 15, .a = 255 });

    for (&balls) |*ball| {
        // Apply gravity
        ball.vy += gravity;

        // Move
        ball.x += ball.vx;
        ball.y += ball.vy;

        const r: f32 = @floatFromInt(ball.radius);

        // Bounce off walls with damping
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

        // Draw ball — bright filled circle + dim glow ring
        const bx: i32 = @intFromFloat(ball.x);
        const by: i32 = @intFromFloat(ball.y);

        // Glow: larger, dim version of colour
        const glow = colour.Colour{
            .r = @as(u8, @intCast(@min(ball.col.r / 3, 255))),
            .g = @as(u8, @intCast(@min(ball.col.g / 3, 255))),
            .b = @as(u8, @intCast(@min(ball.col.b / 3, 255))),
            .a = 255,
        };
        canvasTwo.colourFilledCircle(bx, by, ball.radius + 4, glow);

        // Core bright circle
        canvasTwo.colourFilledCircle(bx, by, ball.radius, ball.col);

        // Specular highlight (white pixel near top-left)
        canvasTwo.colourPutPixel(bx - @divTrunc(ball.radius, 3), by - @divTrunc(ball.radius, 3), colour.Colour.white);
    }

    canvasTwo.render();
}

// ---------------------------------------------------------------------------
// zig_init — exported entry point. JS calls this once after WASM instantiation.
// ---------------------------------------------------------------------------
export fn zig_init() void {
    // 1. Initialize the DOM module
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

    // 10. Instantiate canvases (zero-copy into WASM data-segment globals)
    canvasOne = canvas.Canvas.init(800, 600, &canvas_one_buffer, "canvasOneDiv");
    canvasTwo = canvas.Canvas.init(600, 450, &canvas_two_buffer, "canvasTwoDiv");

    // 11. Run static canvasOne synthwave gallery
    performDemoOnCanvasOne();

    // 12. Setup canvasTwo ball physics
    initBalls();

    // 13. Mark ready
    is_ready = true;

    // 14. Start animation loop (callback 3 = onAnimationTick)
    dom.startAnimationLoop(3);
}
