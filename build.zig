const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ── zigdom (core DOM library) ───────────────────────────────────────────
    const dom_mod = b.addModule("dom", .{
        .root_source_file = b.path("src/dom.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ── colour ──────────────────────────────────────────────────────────────
    const colour_mod = b.addModule("colour", .{
        .root_source_file = b.path("src/colour.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ── html (depends on dom) ───────────────────────────────────────────────
    const html_mod = b.addModule("html", .{
        .root_source_file = b.path("src/html.zig"),
        .target = target,
        .optimize = optimize,
    });
    html_mod.addImport("dom", dom_mod);

    // ── canvas (depends on dom, colour) ─────────────────────────────────────
    const canvas_mod = b.addModule("canvas", .{
        .root_source_file = b.path("src/canvas.zig"),
        .target = target,
        .optimize = optimize,
    });
    canvas_mod.addImport("dom", dom_mod);
    canvas_mod.addImport("colour", colour_mod);

    // ── sound (no project dependencies) ─────────────────────────────────────
    _ = b.addModule("sound", .{
        .root_source_file = b.path("src/sound.zig"),
        .target = target,
        .optimize = optimize,
    });
}
