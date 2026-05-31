const std = @import("std");

pub const MAX_COLOUR_VALUE: u8 = 255;

pub const Colour = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub const white = Colour{ .r = MAX_COLOUR_VALUE, .g = MAX_COLOUR_VALUE, .b = MAX_COLOUR_VALUE, .a = MAX_COLOUR_VALUE };
    pub const black = Colour{ .r = 0, .g = 0, .b = 0, .a = MAX_COLOUR_VALUE };
    pub const empty = Colour{ .r = 0, .g = 0, .b = 0, .a = 0 };

    /// Returns true if the colour is fully transparent/empty (legacy format compatibility)
    pub fn isEmpty(self: Colour) bool {
        return self.r == 0 and self.g == 0 and self.b == 0 and self.a == 0;
    }

    /// Converts the colour to grayscale using luminance weighting formula
    pub fn convertToGrayscale(self: *Colour) void {
        const r_f: f64 = @floatFromInt(self.r);
        const g_f: f64 = @floatFromInt(self.g);
        const b_f: f64 = @floatFromInt(self.b);
        const shade = @as(u8, @intFromFloat(0.299 * r_f + 0.587 * g_f + 0.114 * b_f));
        self.r = shade;
        self.g = shade;
        self.b = shade;
    }
};

// Simple seedable Xorshift PRNG for WASM random colour generation
var rng_state: u64 = 1337;

pub fn seed(s: u64) void {
    if (s != 0) {
        rng_state = s;
    }
}

fn nextRandom() u32 {
    rng_state ^= rng_state << 13;
    rng_state ^= rng_state >> 7;
    rng_state ^= rng_state << 17;
    return @truncate(rng_state);
}

/// Generates a random colour with full opacity
pub fn NewRandomColour() Colour {
    const r = @as(u8, @truncate(nextRandom() % 256));
    const g = @as(u8, @truncate(nextRandom() % 256));
    const b = @as(u8, @truncate(nextRandom() % 256));
    return Colour{ .r = r, .g = g, .b = b, .a = MAX_COLOUR_VALUE };
}
