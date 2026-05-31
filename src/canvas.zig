const std = @import("std");
const dom = @import("dom.zig");
const colour_mod = @import("colour.zig");

pub const Colour = colour_mod.Colour;

pub const Point = struct {
    x: i32,
    y: i32,
};

pub const Canvas = struct {
    width: u32,
    height: u32,
    pixels: []u8,
    active_colour: Colour,
    saved_colour: Colour,
    canvas_handle: dom.Handle,
    ctx_handle: dom.Handle,

    /// Initializes the in-memory Canvas by creating the HTMLCanvasElement
    /// and fetching its 2D rendering context from the browser.
    pub fn init(width: u32, height: u32, pixels: []u8, parent_id: []const u8) Canvas {
        const parent_handle = dom.getElementById(parent_id);
        
        // Use unified low-level element creation
        const canvas_h = dom.canvasCreate(parent_handle, width, height);
        const ctx_h = dom.canvasGetContext(canvas_h);

        return Canvas{
            .width = width,
            .height = height,
            .pixels = pixels,
            .active_colour = Colour.black,
            .saved_colour = Colour.black,
            .canvas_handle = canvas_h,
            .ctx_handle = ctx_h,
        };
    }

    /// Renders the in-memory WASM byte buffer directly onto the browser canvas context
    pub fn render(self: Canvas) void {
        dom.canvasRender(self.canvas_handle, self.ctx_handle, self.pixels.ptr, self.width, self.height);
    }

    /// Clears the entire canvas screen with the specified color
    pub fn clearScreen(self: *Canvas, colour: Colour) void {
        var y: u32 = 0;
        while (y < self.height) : (y += 1) {
            var x: u32 = 0;
            while (x < self.width) : (x += 1) {
                self.colourPutPixel(@intCast(x), @intCast(y), colour);
            }
        }
    }

    /// Set drawing colour
    pub fn setColour(self: *Canvas, colour: Colour) void {
        self.active_colour = colour;
    }

    /// Gets active colour
    pub fn getColour(self: Canvas) Colour {
        return self.active_colour;
    }

    /// Saves the current active colour
    pub fn saveColour(self: *Canvas) void {
        self.saved_colour = self.active_colour;
    }

    /// Switches drawing colour and saves the previous one
    pub fn switchAndSaveColour(self: *Canvas, colour: Colour) void {
        self.saveColour();
        self.setColour(colour);
    }

    /// Restores the previously saved active colour
    pub fn restoreColour(self: *Canvas) void {
        self.setColour(self.saved_colour);
    }

    /// Draws a pixel using the active colour
    pub fn putPixel(self: *Canvas, x: i32, y: i32) void {
        self.colourPutPixel(x, y, self.active_colour);
    }

    /// Draws a pixel at coordinates (x, y) with the specified colour
    pub fn colourPutPixel(self: *Canvas, x: i32, y: i32, colour: Colour) void {
        if (x < 0 or x >= @as(i32, @intCast(self.width)) or y < 0 or y >= @as(i32, @intCast(self.height))) {
            return;
        }

        const offset = (@as(usize, @intCast(x)) * 4) + (@as(usize, @intCast(y)) * 4 * self.width);
        if (offset + 3 >= self.pixels.len) return;

        self.pixels[offset] = colour.r;
        self.pixels[offset + 1] = colour.g;
        self.pixels[offset + 2] = colour.b;
        self.pixels[offset + 3] = colour.a;
    }

    /// Retrieves the colour of the pixel at coordinates (x, y)
    pub fn getPixel(self: Canvas, x: i32, y: i32) ?Colour {
        if (x < 0 or x >= @as(i32, @intCast(self.width)) or y < 0 or y >= @as(i32, @intCast(self.height))) {
            return null;
        }

        const offset = (@as(usize, @intCast(x)) * 4) + (@as(usize, @intCast(y)) * 4 * self.width);
        if (offset + 3 >= self.pixels.len) return null;

        return Colour{
            .r = self.pixels[offset],
            .g = self.pixels[offset + 1],
            .b = self.pixels[offset + 2],
            .a = self.pixels[offset + 3],
        };
    }

    /// Draws a one-pixel line using Bresenham's line algorithm
    pub fn line(self: *Canvas, x1_in: i32, y1_in: i32, x2: i32, y2: i32) void {
        var x1 = x1_in;
        var y1 = y1_in;
        const diffX = @abs(x2 - x1);
        const diffY = @abs(y2 - y1);
        
        const slopeX: i32 = if (x1 < x2) 1 else -1;
        const slopeY: i32 = if (y1 < y2) 1 else -1;
        
        var errVal = @as(i32, @intCast(diffX)) - @as(i32, @intCast(diffY));
        
        while (true) {
            self.putPixel(x1, y1);
            
            if (x1 == x2 and y1 == y2) break;
            
            const errVal2 = 2 * errVal;
            if (errVal2 > -@as(i32, @intCast(diffY))) {
                errVal -= @as(i32, @intCast(diffY));
                x1 += slopeX;
            }
            if (errVal2 < @as(i32, @intCast(diffX))) {
                errVal += @as(i32, @intCast(diffX));
                y1 += slopeY;
            }
        }
    }

    pub fn colourLine(self: *Canvas, x1: i32, y1: i32, x2: i32, y2: i32, colour: Colour) void {
        self.switchAndSaveColour(colour);
        self.line(x1, y1, x2, y2);
        self.restoreColour();
    }

    pub fn linePoint(self: *Canvas, p1: Point, p2: Point) void {
        self.line(p1.x, p1.y, p2.x, p2.y);
    }

    pub fn colourLinePoint(self: *Canvas, p1: Point, p2: Point, colour: Colour) void {
        self.switchAndSaveColour(colour);
        self.linePoint(p1, p2);
        self.restoreColour();
    }

    /// Draws an outline circle using trigonometry
    pub fn circle(self: *Canvas, midX: i32, midY: i32, radius: i32) void {
        const rad: f64 = @floatFromInt(radius);
        var deg: f64 = 0.0;
        while (deg < 6.4) {
            const x: i32 = @intFromFloat(rad * std.math.cos(deg));
            const y: i32 = @intFromFloat(rad * std.math.sin(deg));
            self.putPixel(midX + x, midY + y);
            deg += 0.0025;
        }
    }

    pub fn colourCircle(self: *Canvas, midX: i32, midY: i32, radius: i32, colour: Colour) void {
        self.switchAndSaveColour(colour);
        self.circle(midX, midY, radius);
        self.restoreColour();
    }

    /// Draws a filled circle
    pub fn filledCircle(self: *Canvas, midX: i32, midY: i32, radius: i32) void {
        var y = -radius;
        while (y <= radius) : (y += 1) {
            var x = -radius;
            while (x <= radius) : (x += 1) {
                if (x * x + y * y <= radius * radius) {
                    self.putPixel(midX + x, midY + y);
                }
            }
        }
    }

    pub fn colourFilledCircle(self: *Canvas, midX: i32, midY: i32, radius: i32, colour: Colour) void {
        self.switchAndSaveColour(colour);
        self.filledCircle(midX, midY, radius);
        self.restoreColour();
    }

    /// Draws a circular border ring
    pub fn borderCircle(self: *Canvas, midX: i32, midY: i32, radius: i32, borderWidth: i32) void {
        const innerRadius = radius - borderWidth;
        const innerRadiusSquared = innerRadius * innerRadius;
        const radiusSquared = radius * radius;

        var y = -radius;
        while (y <= radius) : (y += 1) {
            var x = -radius;
            while (x <= radius) : (x += 1) {
                const distSquared = x * x + y * y;
                if (distSquared <= radiusSquared and distSquared > innerRadiusSquared) {
                    self.putPixel(midX + x, midY + y);
                }
            }
        }
    }

    pub fn colourBorderCircle(self: *Canvas, midX: i32, midY: i32, radius: i32, borderWidth: i32, colour: Colour) void {
        self.switchAndSaveColour(colour);
        self.borderCircle(midX, midY, radius, borderWidth);
        self.restoreColour();
    }

    /// Draws a filled rectangle
    pub fn filledRectangle(self: *Canvas, xStart: i32, yStart: i32, width: i32, height: i32) void {
        var x: i32 = 0;
        while (x < width) : (x += 1) {
            var y: i32 = 0;
            while (y < height) : (y += 1) {
                self.putPixel(xStart + x, yStart + y);
            }
        }
    }

    pub fn colourFilledRectangle(self: *Canvas, xStart: i32, yStart: i32, width: i32, height: i32, colour: Colour) void {
        self.switchAndSaveColour(colour);
        self.filledRectangle(xStart, yStart, width, height);
        self.restoreColour();
    }

    /// Draws outline rectangle
    pub fn _rectangle(self: *Canvas, xStart: i32, yStart: i32, width: i32, height: i32) void {
        self.line(xStart, yStart, xStart + width, yStart); // top
        self.line(xStart + width, yStart, xStart + width, yStart + height); // right
        self.line(xStart, yStart + height, xStart + width, yStart + height); // bottom
        self.line(xStart, yStart, xStart, yStart + height); // left
    }

    pub fn rectangle(self: *Canvas, xStart: i32, yStart: i32, width: i32, height: i32, thickness: i32) void {
        _ = thickness;
        self._rectangle(xStart, yStart, width, height);
    }

    pub fn colourRectangle(self: *Canvas, xStart: i32, yStart: i32, width: i32, height: i32, thickness: i32, colour: Colour) void {
        self.switchAndSaveColour(colour);
        self.rectangle(xStart, yStart, width, height, thickness);
        self.restoreColour();
    }

    /// Draws outline triangle between three points
    pub fn triangle(self: *Canvas, p1: Point, p2: Point, p3: Point) void {
        self.linePoint(p1, p2);
        self.linePoint(p2, p3);
        self.linePoint(p1, p3);
    }

    pub fn getContext2D(self: Canvas) dom.Context2D {
        return dom.Context2D{ .ctx = self.ctx_handle };
    }
};
