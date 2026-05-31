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
var canvas_one_time: u32 = 0;
var grid_offset: f64 = 0.0;

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
    current_theme_idx = @mod(current_theme_idx + 1, themes.len);
}

// ------------------------------------------------------------------------------------------------
fn onAnimationTick() void {
    if (!is_ready) return;
    canvas_one_time +%= 1;
    grid_offset += 0.025;
    if (grid_offset >= 1.0) grid_offset -= 1.0;

    performDemoOnCanvasOne();
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
// Theme definitions for Canvas One
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
const Theme = struct {
    bg: colour.Colour,
    panel: colour.Colour,
    cyan: colour.Colour,
    magenta: colour.Colour,
    yellow: colour.Colour,
    violet: colour.Colour,
    sun_start: colour.Colour,
    sun_end: colour.Colour,
    glow_start_str: []const u8,
    glow_mid_str: []const u8,
    glow_end_str: []const u8,
};

// ------------------------------------------------------------------------------------------------
var current_theme_idx: usize = 0;

// ------------------------------------------------------------------------------------------------
const themes = [_]Theme{
    .{
        .bg = colour.Colour{ .r = 5, .g = 5, .b = 16, .a = 255 },
        .panel = colour.Colour{ .r = 12, .g = 12, .b = 36, .a = 255 },
        .cyan = colour.Colour{ .r = 0, .g = 240, .b = 220, .a = 255 },
        .magenta = colour.Colour{ .r = 255, .g = 0, .b = 180, .a = 255 },
        .yellow = colour.Colour{ .r = 255, .g = 230, .b = 0, .a = 255 },
        .violet = colour.Colour{ .r = 160, .g = 0, .b = 255, .a = 255 },
        .sun_start = colour.Colour{ .r = 255, .g = 230, .b = 0, .a = 255 },
        .sun_end = colour.Colour{ .r = 255, .g = 0, .b = 180, .a = 255 },
        .glow_start_str = "rgba(255,0,180,0.12)",
        .glow_mid_str = "rgba(255,180,30,0.22)",
        .glow_end_str = "rgba(255,230,0,0.32)",
    },
    .{
        .bg = colour.Colour{ .r = 12, .g = 4, .b = 4, .a = 255 },
        .panel = colour.Colour{ .r = 24, .g = 8, .b = 8, .a = 255 },
        .cyan = colour.Colour{ .r = 255, .g = 120, .b = 0, .a = 255 },
        .magenta = colour.Colour{ .r = 255, .g = 40, .b = 0, .a = 255 },
        .yellow = colour.Colour{ .r = 255, .g = 200, .b = 0, .a = 255 },
        .violet = colour.Colour{ .r = 100, .g = 0, .b = 0, .a = 255 },
        .sun_start = colour.Colour{ .r = 255, .g = 200, .b = 0, .a = 255 },
        .sun_end = colour.Colour{ .r = 255, .g = 40, .b = 0, .a = 255 },
        .glow_start_str = "rgba(255,40,0,0.12)",
        .glow_mid_str = "rgba(255,120,0,0.22)",
        .glow_end_str = "rgba(255,200,0,0.32)",
    },
    .{
        .bg = colour.Colour{ .r = 20, .g = 10, .b = 30, .a = 255 },
        .panel = colour.Colour{ .r = 40, .g = 20, .b = 60, .a = 255 },
        .cyan = colour.Colour{ .r = 0, .g = 255, .b = 255, .a = 255 },
        .magenta = colour.Colour{ .r = 255, .g = 105, .b = 180, .a = 255 },
        .yellow = colour.Colour{ .r = 255, .g = 255, .b = 150, .a = 255 },
        .violet = colour.Colour{ .r = 138, .g = 43, .b = 226, .a = 255 },
        .sun_start = colour.Colour{ .r = 0, .g = 255, .b = 255, .a = 255 },
        .sun_end = colour.Colour{ .r = 255, .g = 105, .b = 180, .a = 255 },
        .glow_start_str = "rgba(255,105,180,0.12)",
        .glow_mid_str = "rgba(138,43,226,0.22)",
        .glow_end_str = "rgba(0,255,255,0.32)",
    },
    .{
        .bg = colour.Colour{ .r = 2, .g = 8, .b = 4, .a = 255 },
        .panel = colour.Colour{ .r = 4, .g = 16, .b = 8, .a = 255 },
        .cyan = colour.Colour{ .r = 0, .g = 255, .b = 100, .a = 255 },
        .magenta = colour.Colour{ .r = 0, .g = 180, .b = 50, .a = 255 },
        .yellow = colour.Colour{ .r = 200, .g = 255, .b = 200, .a = 255 },
        .violet = colour.Colour{ .r = 0, .g = 80, .b = 20, .a = 255 },
        .sun_start = colour.Colour{ .r = 200, .g = 255, .b = 200, .a = 255 },
        .sun_end = colour.Colour{ .r = 0, .g = 180, .b = 50, .a = 255 },
        .glow_start_str = "rgba(0,180,50,0.12)",
        .glow_mid_str = "rgba(0,80,20,0.22)",
        .glow_end_str = "rgba(0,255,100,0.32)",
    },
};

// ------------------------------------------------------------------------------------------------
fn performDemoOnCanvasOne() void {
    const w: i32 = @intCast(canvasOne.width);
    const h: i32 = @intCast(canvasOne.height);
    const horizon = @divTrunc(h, 2) + 50;
    const active_theme = themes[current_theme_idx];

    // Cross-seed colour PRNG from the demo PRNG so each refresh looks different.
    colour.seed(@as(u64, nextRandom()) | 1);

    canvasOne.clearScreen(active_theme.bg);
    canvasOne.colourRectangle(8, 8, w - 16, h - 16, 2, active_theme.panel);

    drawStarfield(w, horizon, canvas_one_time, active_theme);
    drawRetroSun(@divTrunc(w, 2), horizon - 20, 85, active_theme);
    drawMountainSilhouettes(w, horizon, active_theme);
    drawLaserGrid(w, h, horizon, grid_offset, active_theme);
    drawVectorShip(@divTrunc(w, 2), h - 55, canvas_one_time, active_theme);

    canvasOne.render();

    drawSunGlow(canvasOne.getContext2D(), w, horizon - 20, canvas_one_time, active_theme);
}

// ------------------------------------------------------------------------------------------------
fn drawStarfield(w: i32, horizon: i32, time: u32, t: Theme) void {
    colour.seed(999);
    var i: i32 = 0;
    while (i < 90) : (i += 1) {
        const rx = @as(i32, @intCast(colour.randomColour().r)) * 3 + @mod(@as(i32, @intCast(colour.randomColour().g)), 50);
        const ry = @mod(@as(i32, @intCast(colour.randomColour().b)), horizon - 30);
        if (rx < 12 or rx >= w - 12 or ry < 12) continue;

        const r_val = colour.randomColour().g;
        const twinkle_phase = @mod(r_val +% @as(u8, @intCast(@mod(time, 256))), 12);
        if (twinkle_phase == 0) continue;

        const dice = r_val % 8;
        if (dice == 0) {
            canvasOne.colourPutPixel(rx, ry, colour.Colour.white);
            if (twinkle_phase > 2) {
                canvasOne.colourPutPixel(rx - 1, ry, t.cyan);
                canvasOne.colourPutPixel(rx + 1, ry, t.cyan);
                canvasOne.colourPutPixel(rx, ry - 1, t.magenta);
                canvasOne.colourPutPixel(rx, ry + 1, t.magenta);
            }
        } else if (dice < 3) {
            canvasOne.colourPutPixel(rx, ry, t.magenta);
        } else if (dice < 6) {
            canvasOne.colourPutPixel(rx, ry, t.cyan);
        } else {
            canvasOne.colourPutPixel(rx, ry, colour.Colour.white);
        }
    }
}

// ------------------------------------------------------------------------------------------------
fn drawRetroSun(cx: i32, cy: i32, r: i32, t: Theme) void {
    var dy = -r;
    while (dy <= r) : (dy += 1) {
        const y = cy + dy;
        const r_f: f64 = @floatFromInt(r);
        const dy_f: f64 = @floatFromInt(dy);
        const chord: i32 = @intFromFloat(@sqrt(r_f * r_f - dy_f * dy_f));

        if (dy > 0) {
            const val = @mod(dy, 12);
            if (val < @divTrunc(dy, 6) + 1) {
                continue;
            }
        }

        const ratio = @as(f32, @floatFromInt(dy + r)) / @as(f32, @floatFromInt(2 * r));
        const red: u8 = @intFromFloat(@as(f32, @floatFromInt(t.sun_start.r)) * (1.0 - ratio) + @as(f32, @floatFromInt(t.sun_end.r)) * ratio);
        const green: u8 = @intFromFloat(@as(f32, @floatFromInt(t.sun_start.g)) * (1.0 - ratio) + @as(f32, @floatFromInt(t.sun_end.g)) * ratio);
        const blue: u8 = @intFromFloat(@as(f32, @floatFromInt(t.sun_start.b)) * (1.0 - ratio) + @as(f32, @floatFromInt(t.sun_end.b)) * ratio);
        const c = colour.Colour{ .r = red, .g = green, .b = blue, .a = 255 };

        canvasOne.colourLine(cx - chord, y, cx + chord, y, c);
    }
}

// ------------------------------------------------------------------------------------------------
fn drawMountainSilhouettes(w: i32, horizon: i32, t: Theme) void {
    const bg_pts = [_][2]i32{
        .{ 8, horizon },
        .{ 120, horizon - 75 },
        .{ 240, horizon - 25 },
        .{ 350, horizon - 105 },
        .{ 480, horizon - 45 },
        .{ 620, horizon - 95 },
        .{ 710, horizon - 35 },
        .{ w - 8, horizon },
    };

    const fg_pts = [_][2]i32{
        .{ 8, horizon },
        .{ 90, horizon - 40 },
        .{ 180, horizon - 15 },
        .{ 290, horizon - 65 },
        .{ 390, horizon - 30 },
        .{ 510, horizon - 75 },
        .{ 640, horizon - 20 },
        .{ 730, horizon - 50 },
        .{ w - 8, horizon },
    };

    var idx: usize = 0;
    while (idx < bg_pts.len - 1) : (idx += 1) {
        const p1 = bg_pts[idx];
        const p2 = bg_pts[idx + 1];
        var x = p1[0];
        while (x <= p2[0]) : (x += 1) {
            const ratio = @as(f32, @floatFromInt(x - p1[0])) / @as(f32, @floatFromInt(p2[0] - p1[0]));
            const y: i32 = @intFromFloat((1.0 - ratio) * @as(f32, @floatFromInt(p1[1])) + ratio * @as(f32, @floatFromInt(p2[1])));
            canvasOne.colourLine(x, y + 1, x, horizon, t.bg);
        }
    }

    idx = 0;
    while (idx < bg_pts.len - 1) : (idx += 1) {
        canvasOne.colourLine(bg_pts[idx][0], bg_pts[idx][1], bg_pts[idx + 1][0], bg_pts[idx + 1][1], t.violet);
    }

    idx = 0;
    while (idx < fg_pts.len - 1) : (idx += 1) {
        const p1 = fg_pts[idx];
        const p2 = fg_pts[idx + 1];
        var x = p1[0];
        while (x <= p2[0]) : (x += 1) {
            const ratio = @as(f32, @floatFromInt(x - p1[0])) / @as(f32, @floatFromInt(p2[0] - p1[0]));
            const y: i32 = @intFromFloat((1.0 - ratio) * @as(f32, @floatFromInt(p1[1])) + ratio * @as(f32, @floatFromInt(p2[1])));
            canvasOne.colourLine(x, y + 1, x, horizon, t.bg);
        }
    }

    idx = 0;
    while (idx < fg_pts.len - 1) : (idx += 1) {
        canvasOne.colourLine(fg_pts[idx][0], fg_pts[idx][1], fg_pts[idx + 1][0], fg_pts[idx + 1][1], t.cyan);
    }
}

// ------------------------------------------------------------------------------------------------
fn drawLaserGrid(w: i32, h: i32, horizon: i32, scroll_offset: f64, t: Theme) void {
    var x: i32 = -120;
    while (x <= w + 120) : (x += 35) {
        canvasOne.colourLine(@divTrunc(w, 2), horizon, x, h, t.violet);
        canvasOne.colourLine(@divTrunc(w, 2), horizon + 2, x, h, t.cyan);
    }

    var i: f64 = 0.0;
    while (true) {
        const exponent = i + scroll_offset;
        const dist = 6.0 * std.math.pow(f64, 1.25, exponent);
        const y = horizon + @as(i32, @intCast(@as(i64, @intFromFloat(dist))));
        if (y >= h - 8) break;
        if (y >= horizon + 8) {
            canvasOne.colourLine(10, y, w - 10, y, t.violet);
            canvasOne.colourLine(10, y, w - 10, y, t.magenta);
        }
        i += 1.0;
    }
}

// ------------------------------------------------------------------------------------------------
fn drawVectorShip(cx: i32, cy: i32, time: u32, t: Theme) void {
    const time_f = @as(f32, @floatFromInt(time));
    const bob_y = @as(i32, @intFromFloat(4.0 * std.math.sin(time_f * 0.06)));
    const sway_x = @as(i32, @intFromFloat(5.0 * std.math.cos(time_f * 0.04)));

    const scx = cx + sway_x;
    const scy = cy + bob_y;

    const flame_len = @as(i32, @intFromFloat(26.0 + 4.0 * std.math.sin(time_f * 0.25)));

    canvasOne.colourLine(scx - 8, scy + 12, scx, scy + flame_len, t.cyan);
    canvasOne.colourLine(scx + 8, scy + 12, scx, scy + flame_len, t.cyan);
    canvasOne.colourLine(scx - 8, scy + 12, scx + 8, scy + 12, t.cyan);

    canvasOne.colourLine(scx - 35, scy + 10, scx + 35, scy + 10, t.magenta);
    canvasOne.colourLine(scx - 35, scy + 10, scx - 12, scy - 20, t.magenta);
    canvasOne.colourLine(scx + 35, scy + 10, scx + 12, scy - 20, t.magenta);

    canvasOne.colourLine(scx - 12, scy - 20, scx, scy - 40, t.yellow);
    canvasOne.colourLine(scx + 12, scy - 20, scx, scy - 40, t.yellow);
    canvasOne.colourLine(scx - 12, scy - 20, scx + 12, scy - 20, t.yellow);

    canvasOne.colourLine(scx - 6, scy - 10, scx, scy - 25, t.cyan);
    canvasOne.colourLine(scx + 6, scy - 10, scx, scy - 25, t.cyan);
    canvasOne.colourLine(scx - 6, scy - 10, scx + 6, scy - 10, t.cyan);
}

// ------------------------------------------------------------------------------------------------
fn drawSunGlow(ctx: dom.Context2D, w: i32, cy: i32, time: u32, t: Theme) void {
    const cx_f: f64 = @floatFromInt(@divTrunc(w, 2));
    const cy_f: f64 = @floatFromInt(cy);
    const time_f = @as(f64, @floatFromInt(time));
    const pulse = 3.0 * std.math.sin(time_f * 0.05);

    ctx.beginPath();
    ctx.fillStyle(t.glow_start_str);
    ctx.arc(cx_f, cy_f, 130.0 + pulse, 0.0, 6.2832, false);
    ctx.fill();

    ctx.beginPath();
    ctx.fillStyle(t.glow_mid_str);
    ctx.arc(cx_f, cy_f, 95.0 - pulse, 0.0, 6.2832, false);
    ctx.fill();

    ctx.beginPath();
    ctx.fillStyle(t.glow_end_str);
    ctx.arc(cx_f, cy_f, 50.0 + pulse, 0.0, 6.2832, false);
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
