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
        const optimized_install_step = b.addInstallFile(optimized_wasm_lazy_path, "lib/zip8.wasm");
        b.default_step.dependOn(&optimized_install_step.step);
    } else {
        // This declares intent for the executable to be installed into the
        // standard location when the user invokes the "install" step (the default
        // step when running `zig build`).
        b.installArtifact(wasm_library);
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
    b.installArtifact(rp2040_library);

    const zip_root = b.makeTempPath();

    const m0plus_dir = std.fs.path.resolve(b.allocator, &.{ zip_root, "zip8", "src", "cortex-m0plus" }) catch @panic("OOM");
    const src_dir = m0plus_dir[0..(m0plus_dir.len - "/cortex-m0plus".len)];
    const zip8_dir = src_dir[0..(src_dir.len - "/src".len)];

    const create_directories = b.addSystemCommand(&.{ "mkdir", "-p", m0plus_dir });
    const copy_library_properties = b.addSystemCommand(&.{ "cp", b.pathFromRoot("library.properties"), zip8_dir });
    copy_library_properties.step.dependOn(&create_directories.step);
    const copy_header = b.addSystemCommand(&.{ "cp", b.pathFromRoot("src/zip8.h"), src_dir });
    copy_header.step.dependOn(&create_directories.step);
    const copy_library = b.addSystemCommand(&.{"cp"});
    copy_library.addArtifactArg(rp2040_library);
    copy_library.addArg(m0plus_dir);
    copy_library.step.dependOn(&create_directories.step);

    const zip_step = b.addSystemCommand(&.{ "zip", "-r" });
    zip_step.cwd = zip_root;
    const zip_lazy_path = zip_step.addOutputFileArg("zip8.zip");
    zip_step.step.dependencies.appendSlice(&.{
        &copy_library_properties.step,
        &copy_header.step,
        &copy_library.step,
    }) catch @panic("OOM");
    zip_step.addArg("zip8");
    const zip_install_step = b.addInstallFile(zip_lazy_path, "lib/zip8.zip");
    b.default_step.dependOn(&zip_install_step.step);

    // make a "library" zip file which can be installed in the Arduino IDE

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
