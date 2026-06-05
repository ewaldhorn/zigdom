const std = @import("std");
const dom = @import("dom");
const colour_mod = @import("colour");

// ------------------------------------------------------------------------------------------------
pub const Colour = colour_mod.Colour;

// ------------------------------------------------------------------------------------------------
pub const Point = struct {
    x: i32,
    y: i32,
};

// ------------------------------------------------------------------------------------------------
pub const Canvas = struct {
    width: u32,
    height: u32,
    pixels: []u8,
    /// Active drawing colour used by non-colour-variant methods.
    active_colour: Colour,
    canvas_handle: dom.Handle,
    ctx_handle: dom.Handle,

    // --------------------------------------------------------------------------------------------
    // Lifecycle
    // --------------------------------------------------------------------------------------------

    // --------------------------------------------------------------------------------------------
    /// Initialises the in-memory Canvas: creates the HTMLCanvasElement in the
    /// browser under `parent_id` and fetches its 2D rendering context.
    pub fn init(width: u32, height: u32, pixels: []u8, parent_id: []const u8) Canvas {
        std.debug.assert(pixels.len >= width * height * 4);
        const parent_handle = dom.getElementById(parent_id);
        const canvas_h = dom.canvasCreate(parent_handle, width, height);
        const ctx_h = dom.canvasGetContext(canvas_h);
        return .{
            .width = width,
            .height = height,
            .pixels = pixels,
            .active_colour = Colour.black,
            .canvas_handle = canvas_h,
            .ctx_handle = ctx_h,
        };
    }

    // --------------------------------------------------------------------------------------------
    /// Blits the in-memory WASM pixel buffer directly onto the browser canvas.
    /// Zero-copy: JS creates a `Uint8ClampedArray` view on top of WASM memory.
    pub fn render(self: Canvas) void {
        dom.canvasRender(self.canvas_handle, self.ctx_handle, self.pixels.ptr, self.width, self.height);
    }

    // --------------------------------------------------------------------------------------------
    // Pixel offset helper (private)
    // --------------------------------------------------------------------------------------------

    // --------------------------------------------------------------------------------------------
    /// Returns the byte offset of pixel (x, y) in the pixel buffer,
    /// or null if (x, y) lies outside the canvas bounds.
    /// Declared `inline` so the branch is fused into every call site.
    inline fn pixelOffset(self: Canvas, x: i32, y: i32) ?usize {
        if (x < 0 or y < 0) return null;
        const ux: u32 = @intCast(x);
        const uy: u32 = @intCast(y);
        if (ux >= self.width or uy >= self.height) return null;
        return (@as(usize, uy) * @as(usize, self.width) + @as(usize, ux)) * 4;
    }

    // --------------------------------------------------------------------------------------------
    // Fill / clear
    // --------------------------------------------------------------------------------------------

    // --------------------------------------------------------------------------------------------
    /// Fills the entire pixel buffer with a single colour.
    /// Writes 4 bytes per iteration — no per-pixel bounds checking or
    /// offset arithmetic. Far cheaper than routing through `colourPutPixel`.
    pub fn clearScreen(self: *Canvas, c: Colour) void {
        var i: usize = 0;
        const len = self.pixels.len;
        while (i < len) : (i += 4) {
            self.pixels[i] = c.r;
            self.pixels[i + 1] = c.g;
            self.pixels[i + 2] = c.b;
            self.pixels[i + 3] = c.a;
        }
    }

    // --------------------------------------------------------------------------------------------
    // Colour state
    // --------------------------------------------------------------------------------------------

    // --------------------------------------------------------------------------------------------
    /// Sets the active drawing colour (used by `putPixel`, `line`, `circle`, etc.).
    pub fn setColour(self: *Canvas, c: Colour) void {
        self.active_colour = c;
    }

    // --------------------------------------------------------------------------------------------
    /// Returns the current active drawing colour.
    pub fn getColour(self: Canvas) Colour {
        return self.active_colour;
    }

    // --------------------------------------------------------------------------------------------
    // Pixel primitives
    // --------------------------------------------------------------------------------------------

    // --------------------------------------------------------------------------------------------
    /// Draws one pixel using the active colour. No-op when out of bounds.
    pub fn putPixel(self: *Canvas, x: i32, y: i32) void {
        const off = self.pixelOffset(x, y) orelse return;
        self.pixels[off] = self.active_colour.r;
        self.pixels[off + 1] = self.active_colour.g;
        self.pixels[off + 2] = self.active_colour.b;
        self.pixels[off + 3] = self.active_colour.a;
    }

    // --------------------------------------------------------------------------------------------
    /// Draws one pixel with an explicit colour. No-op when out of bounds.
    pub fn colourPutPixel(self: *Canvas, x: i32, y: i32, c: Colour) void {
        const off = self.pixelOffset(x, y) orelse return;
        self.pixels[off] = c.r;
        self.pixels[off + 1] = c.g;
        self.pixels[off + 2] = c.b;
        self.pixels[off + 3] = c.a;
    }

    // --------------------------------------------------------------------------------------------
    /// Returns the colour of pixel (x, y), or null if out of bounds.
    pub fn getPixel(self: Canvas, x: i32, y: i32) ?Colour {
        const off = self.pixelOffset(x, y) orelse return null;
        return .{
            .r = self.pixels[off],
            .g = self.pixels[off + 1],
            .b = self.pixels[off + 2],
            .a = self.pixels[off + 3],
        };
    }

    // --------------------------------------------------------------------------------------------
    // Lines
    // --------------------------------------------------------------------------------------------

    // --------------------------------------------------------------------------------------------
    /// Draws a 1-pixel line via Bresenham's algorithm. Uses the active colour.
    pub fn line(self: *Canvas, x1_in: i32, y1_in: i32, x2: i32, y2: i32) void {
        var x1 = x1_in;
        var y1 = y1_in;
        const diffX = @abs(x2 - x1);
        const diffY = @abs(y2 - y1);
        const slopeX: i32 = if (x1 < x2) 1 else -1;
        const slopeY: i32 = if (y1 < y2) 1 else -1;
        var err: i32 = @as(i32, @intCast(diffX)) - @as(i32, @intCast(diffY));
        while (true) {
            self.putPixel(x1, y1);
            if (x1 == x2 and y1 == y2) break;
            const e2 = 2 * err;
            if (e2 > -@as(i32, @intCast(diffY))) {
                err -= @as(i32, @intCast(diffY));
                x1 += slopeX;
            }
            if (e2 < @as(i32, @intCast(diffX))) {
                err += @as(i32, @intCast(diffX));
                y1 += slopeY;
            }
        }
    }

    // --------------------------------------------------------------------------------------------
    /// Draws a line with an explicit colour.
    pub fn colourLine(self: *Canvas, x1: i32, y1: i32, x2: i32, y2: i32, c: Colour) void {
        self.active_colour = c;
        self.line(x1, y1, x2, y2);
    }

    // --------------------------------------------------------------------------------------------
    /// Draws a line between two Points using the active colour.
    pub fn linePoint(self: *Canvas, p1: Point, p2: Point) void {
        self.line(p1.x, p1.y, p2.x, p2.y);
    }

    // --------------------------------------------------------------------------------------------
    /// Draws a line between two Points with an explicit colour.
    pub fn colourLinePoint(self: *Canvas, p1: Point, p2: Point, c: Colour) void {
        self.active_colour = c;
        self.linePoint(p1, p2);
    }

    // --------------------------------------------------------------------------------------------
    // Circles
    // --------------------------------------------------------------------------------------------

    // --------------------------------------------------------------------------------------------
    /// Draws a 1-pixel outline circle using the active colour.
    /// The angular step is `1/radius` radians so approximately one pixel is
    /// painted per step regardless of circle size (no gaps, no excess overdraw).
    pub fn circle(self: *Canvas, midX: i32, midY: i32, radius: i32) void {
        if (radius <= 0) return;
        const rad: f64 = @floatFromInt(radius);
        const step = 1.0 / rad;
        var deg: f64 = 0.0;
        while (deg < 2.0 * std.math.pi) : (deg += step) {
            const x: i32 = @intFromFloat(rad * std.math.cos(deg));
            const y: i32 = @intFromFloat(rad * std.math.sin(deg));
            self.putPixel(midX + x, midY + y);
        }
    }

    // --------------------------------------------------------------------------------------------
    /// Draws an outline circle with an explicit colour.
    pub fn colourCircle(self: *Canvas, midX: i32, midY: i32, radius: i32, c: Colour) void {
        self.active_colour = c;
        self.circle(midX, midY, radius);
    }

    // --------------------------------------------------------------------------------------------
    /// Draws a filled circle using the active colour.
    /// Uses chord-width iteration: O(radius) rows × O(chord) pixels per row.
    /// No per-pixel distance test — eliminates the inner multiply-compare of
    /// the naïve O(radius²) bounding-box scan.
    pub fn filledCircle(self: *Canvas, midX: i32, midY: i32, radius: i32) void {
        if (radius <= 0) return;
        const r2 = radius * radius;
        var dy = -radius;
        while (dy <= radius) : (dy += 1) {
            const chord: i32 = @intFromFloat(@sqrt(@as(f64, @floatFromInt(r2 - dy * dy))));
            var dx = -chord;
            while (dx <= chord) : (dx += 1) {
                self.putPixel(midX + dx, midY + dy);
            }
        }
    }

    // --------------------------------------------------------------------------------------------
    /// Draws a filled circle with an explicit colour.
    pub fn colourFilledCircle(self: *Canvas, midX: i32, midY: i32, radius: i32, c: Colour) void {
        self.active_colour = c;
        self.filledCircle(midX, midY, radius);
    }

    // --------------------------------------------------------------------------------------------
    /// Draws a ring (annulus) — the area between `radius` and `radius - borderWidth`.
    pub fn borderCircle(self: *Canvas, midX: i32, midY: i32, radius: i32, borderWidth: i32) void {
        if (radius <= 0) return;
        if (borderWidth <= 0) return;
        const innerRadius = radius - borderWidth;
        if (innerRadius <= 0) {
            self.filledCircle(midX, midY, radius);
            return;
        }
        const outerR2 = radius * radius;
        const innerR2 = innerRadius * innerRadius;
        var dy = -radius;
        while (dy <= radius) : (dy += 1) {
            var dx = -radius;
            while (dx <= radius) : (dx += 1) {
                const d2 = dx * dx + dy * dy;
                if (d2 <= outerR2 and d2 > innerR2) self.putPixel(midX + dx, midY + dy);
            }
        }
    }

    // --------------------------------------------------------------------------------------------
    /// Draws a ring with an explicit colour.
    pub fn colourBorderCircle(self: *Canvas, midX: i32, midY: i32, radius: i32, borderWidth: i32, c: Colour) void {
        self.active_colour = c;
        self.borderCircle(midX, midY, radius, borderWidth);
    }

    // --------------------------------------------------------------------------------------------
    // Rectangles
    // --------------------------------------------------------------------------------------------

    // --------------------------------------------------------------------------------------------
    /// Draws a filled rectangle using the active colour.
    /// Iterates rows first (y outer) for row-major cache friendliness.
    pub fn filledRectangle(self: *Canvas, xStart: i32, yStart: i32, width: i32, height: i32) void {
        var y: i32 = 0;
        while (y < height) : (y += 1) {
            var x: i32 = 0;
            while (x < width) : (x += 1) {
                self.putPixel(xStart + x, yStart + y);
            }
        }
    }

    // --------------------------------------------------------------------------------------------
    /// Draws a filled rectangle with an explicit colour.
    pub fn colourFilledRectangle(self: *Canvas, xStart: i32, yStart: i32, width: i32, height: i32, c: Colour) void {
        self.active_colour = c;
        self.filledRectangle(xStart, yStart, width, height);
    }

    // --------------------------------------------------------------------------------------------
    /// Draws a single-pixel outline rectangle (private helper).
    fn rectangleOutline(self: *Canvas, xStart: i32, yStart: i32, width: i32, height: i32) void {
        self.line(xStart, yStart, xStart + width, yStart); // top
        self.line(xStart + width, yStart, xStart + width, yStart + height); // right
        self.line(xStart, yStart + height, xStart + width, yStart + height); // bottom
        self.line(xStart, yStart, xStart, yStart + height); // left
    }

    // --------------------------------------------------------------------------------------------
    /// Draws an outline rectangle with the specified border `thickness` (drawn inward).
    /// Each thickness level draws one nested outline rectangle.
    pub fn rectangle(self: *Canvas, xStart: i32, yStart: i32, width: i32, height: i32, thickness: i32) void {
        var t: i32 = 0;
        while (t < thickness) : (t += 1) {
            if (width - t * 2 < 0 or height - t * 2 < 0) break;
            self.rectangleOutline(xStart + t, yStart + t, width - t * 2, height - t * 2);
        }
    }

    // --------------------------------------------------------------------------------------------
    /// Draws an outline rectangle with an explicit colour and border thickness.
    pub fn colourRectangle(self: *Canvas, xStart: i32, yStart: i32, width: i32, height: i32, thickness: i32, c: Colour) void {
        self.active_colour = c;
        self.rectangle(xStart, yStart, width, height, thickness);
    }

    // --------------------------------------------------------------------------------------------
    // Triangles
    // --------------------------------------------------------------------------------------------

    // --------------------------------------------------------------------------------------------
    /// Draws a wireframe triangle between three Points using the active colour.
    pub fn triangle(self: *Canvas, p1: Point, p2: Point, p3: Point) void {
        self.linePoint(p1, p2);
        self.linePoint(p2, p3);
        self.linePoint(p1, p3);
    }

    // --------------------------------------------------------------------------------------------
    // Canvas 2D context access
    // --------------------------------------------------------------------------------------------

    // --------------------------------------------------------------------------------------------
    /// Returns a `Context2D` wrapper for direct Canvas 2D API calls via JS.
    pub fn getContext2D(self: Canvas) dom.Context2D {
        return .{ .ctx = self.ctx_handle };
    }
};
