const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const optimize: std.builtin.OptimizeMode = .ReleaseSmall;

    // ── Dependency: zigdom library ──────────────────────────────────────────
    const zigdom_dep = b.dependency("zigdom", .{
        .target = target,
        .optimize = optimize,
    });

    // ── WASM executable (no entry point — JS drives everything) ─────────────
    const exe = b.addExecutable(.{
        .name = "zigdom",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/demo.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Wire library modules to the demo
    exe.root_module.addImport("dom", zigdom_dep.module("dom"));
    exe.root_module.addImport("html", zigdom_dep.module("html"));
    exe.root_module.addImport("colour", zigdom_dep.module("colour"));
    exe.root_module.addImport("canvas", zigdom_dep.module("canvas"));
    exe.root_module.addImport("sound", zigdom_dep.module("sound"));

    // WASM-specific: no entry, export all public symbols
    exe.entry = .disabled;
    exe.rdynamic = true;

    // ── Install the WASM binary to ../docs/ ─────────────────────────────────
    const wasm_path = exe.getEmittedBin();
    const install_step = b.step("install-wasm", "Install zigdom.wasm → ../docs/");

    const cp = b.addSystemCommand(&.{ "cp", "-f" });
    cp.addFileArg(wasm_path);
    cp.addArg("../docs/zigdom.wasm");
    cp.step.dependOn(&exe.step);
    install_step.dependOn(&cp.step);

    b.default_step = install_step;
}
