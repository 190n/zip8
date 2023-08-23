const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    const wasm_library = b.addSharedLibrary(.{
        .name = "zip8",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = .{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
            .cpu_features_add = std.Target.wasm.featureSet(&.{.bulk_memory}),
        },
        .optimize = optimize,
    });
    wasm_library.rdynamic = true;

    const wasm_step = b.step("wasm", "Build WebAssembly library");

    if (optimize == .ReleaseSmall) {
        // use wasm-opt to make binary smaller
        const run_wasm_opt = b.addSystemCommand(&.{
            "wasm-opt",
            "-Oz",
            "--enable-bulk-memory",
            "--enable-sign-ext",
        });
        run_wasm_opt.addArtifactArg(wasm_library);
        run_wasm_opt.addArg("-o");
        const optimized_wasm_lazy_path = run_wasm_opt.addOutputFileArg("zip8.wasm");
        const optimized_install_step = b.addInstallLibFile(optimized_wasm_lazy_path, "zip8.wasm");
        wasm_step.dependOn(&optimized_install_step.step);
    } else {
        // This declares intent for the executable to be installed into the
        // standard location when the user invokes the "install" step (the default
        // step when running `zig build`).
        const wasm_install = b.addInstallLibFile(wasm_library.getEmittedBin(), "zip8.wasm");
        wasm_step.dependOn(&wasm_install.step);
    }

    // build a static library for ARM Cortex-M0+, suitable for RP2040
    const rp2040_library = b.addStaticLibrary(.{
        .name = "zip8",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = .{
            .cpu_arch = .thumb,
            .os_tag = .freestanding,
            .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m0plus },
        },
        .optimize = optimize,
    });
    const rp2040_library_install = b.addInstallLibFile(rp2040_library.getEmittedBin(), "libzip8.a");

    // make a "library" zip file which can be installed in the Arduino IDE
    const write_files_step = b.addWriteFiles();
    _ = write_files_step.addCopyFile(rp2040_library.getEmittedBin(), "zip8/src/cortex-m0plus/libzip8.a");
    _ = write_files_step.addCopyFile(std.build.LazyPath.relative("src/zip8.h"), "zip8/src/zip8.h");
    _ = write_files_step.addCopyFile(std.build.LazyPath.relative("library.properties"), "zip8/library.properties");
    const zip_step = b.addSystemCommand(&.{ "sh", "-c", "cd $0; zip -r $1 zip8" });
    zip_step.addDirectoryArg(write_files_step.getDirectory());
    const zip_output = zip_step.addOutputFileArg("zip8.zip");
    const zip_install_step = b.addInstallFile(zip_output, "lib/zip8.zip");

    const arduino_step = b.step("arduino", "Build .zip Arduino library for RP2040 and other Cortex-M0+ chips");
    arduino_step.dependOn(&zip_install_step.step);
    arduino_step.dependOn(&rp2040_library_install.step);

    b.default_step.dependOn(wasm_step);
    b.default_step.dependOn(arduino_step);

    // Creates a step for unit testing.
    const exe_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    const test_run_cmd = b.addRunArtifact(exe_tests.step.cast(std.build.Step.Compile).?);
    test_step.dependOn(&test_run_cmd.step);
}
