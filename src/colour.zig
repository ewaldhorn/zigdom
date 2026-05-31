const std = @import("std");

pub const Colour = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub const white = Colour{ .r = 255, .g = 255, .b = 255, .a = 255 };
    pub const black = Colour{ .r = 0,   .g = 0,   .b = 0,   .a = 255 };
    pub const empty = Colour{ .r = 0,   .g = 0,   .b = 0,   .a = 0   };

    /// Returns true if the colour is fully transparent.
    pub fn isEmpty(self: Colour) bool {
        return self.r == 0 and self.g == 0 and self.b == 0 and self.a == 0;
    }

    /// Converts the colour to grayscale in-place using luminance weighting.
    pub fn convertToGrayscale(self: *Colour) void {
        const r: f32 = @floatFromInt(self.r);
        const g: f32 = @floatFromInt(self.g);
        const b: f32 = @floatFromInt(self.b);
        const shade: u8 = @intFromFloat(0.299 * r + 0.587 * g + 0.114 * b);
        self.r = shade;
        self.g = shade;
        self.b = shade;
    }
};

// ---------------------------------------------------------------------------
// Seedable Xorshift64 PRNG — allocation-free random colour generation.
// ---------------------------------------------------------------------------
var rng_state: u64 = 1337;

/// Re-seeds the colour PRNG. `s` must be non-zero; zero is silently ignored.
pub fn seed(s: u64) void {
    if (s != 0) rng_state = s;
}

fn nextRandom() u32 {
    rng_state ^= rng_state << 13;
    rng_state ^= rng_state >> 7;
    rng_state ^= rng_state << 17;
    return @truncate(rng_state);
}

/// Returns a random fully-opaque colour.
/// Each channel is an independent PRNG draw; `@truncate` from u32 to u8
/// is already a modulo-256, so no explicit `% 256` is needed.
pub fn randomColour() Colour {
    return .{
        .r = @truncate(nextRandom()),
        .g = @truncate(nextRandom()),
        .b = @truncate(nextRandom()),
        .a = 255,
    };
}
