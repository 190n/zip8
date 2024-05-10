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
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });

    const use_avr_gcc = b.option(
        bool,
        "use_avr_gcc",
        "Use C backend and AVR GCC to compile the AVR library instead of LLVM AVR backend",
    ) orelse false;

    const memory_size = b.option(
        u13,
        "memory_size",
        "Size of the CHIP-8's memory. Higher than 4096 is unacceptable; lower than 4096 may break some programs.",
    );

    const column_major_display = b.option(
        bool,
        "column_major_display",
        "Whether the display should use column-major layout instead of row-major. Default false.",
    ) orelse false;

    const options = b.addOptions();
    options.addOption(?u13, "memory_size", memory_size);
    options.addOption(bool, "column_major_display", column_major_display);
    const options_module = options.createModule();

    const native_library = b.addSharedLibrary(.{
        .name = "zip8",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    native_library.root_module.addImport("build_options", options_module);
    const native_library_install = b.addInstallLibFile(
        native_library.getEmittedBin(),
        b.fmt("libzip8{s}", .{target.result.dynamicLibSuffix()}),
    );

    const wasm_library = b.addExecutable(.{
        .name = "zip8",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
            .cpu_features_add = std.Target.wasm.featureSet(&.{.bulk_memory}),
        }),
        .optimize = optimize,
    });
    wasm_library.entry = .disabled;
    wasm_library.root_module.addImport("build_options", options_module);
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
    const m0plus_library = b.addStaticLibrary(.{
        .name = "zip8",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .thumb,
            .os_tag = .freestanding,
            .abi = .eabi,
            .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m0plus },
        }),
        .optimize = optimize,
    });
    m0plus_library.root_module.addImport("build_options", options_module);
    const m0plus_library_install = b.addInstallLibFile(m0plus_library.getEmittedBin(), "cortex-m0plus/libzip8.a");

    // build a static library for AVR
    const atmega4809_library = b.addStaticLibrary(.{
        .name = "zip8",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .avr,
            .os_tag = .freestanding,
            .cpu_model = .{ .explicit = &std.Target.avr.cpu.atmega4809 },
            .ofmt = if (use_avr_gcc) .c else null,
        }),
        .optimize = optimize,
    });
    atmega4809_library.root_module.addImport("build_options", options_module);

    const atmega4809_library_file = if (use_avr_gcc) bin: {
        const gcc_cmd = b.addSystemCommand(&.{
            "sh",
            "-c",
            "avr-gcc -c -Wno-incompatible-pointer-types -Wno-builtin-declaration-mismatch -mmcu=atmega4809 $0 -I $1 $2 -o $3",
            switch (optimize) {
                .Debug => "-g",
                .ReleaseSafe => "-O3",
                .ReleaseFast => "-O3",
                .ReleaseSmall => "-Oz",
            },
        });
        gcc_cmd.addArg(b.lib_dir);
        gcc_cmd.addFileArg(atmega4809_library.getEmittedBin());

        const avr_object_path = gcc_cmd.addOutputFileArg("zip8.o");

        const ar_cmd = b.addSystemCommand(&.{ "ar", "-rcs" });
        const avr_library_path = ar_cmd.addOutputFileArg("libzip8.a");
        ar_cmd.addFileArg(avr_object_path);

        break :bin avr_library_path;
    } else bin: {
        break :bin atmega4809_library.getEmittedBin();
    };
    const atmega4809_library_install = b.addInstallLibFile(atmega4809_library_file, "atmega4809/libzip8.a");

    // make a "library" zip file which can be installed in the Arduino IDE
    const write_files_step = b.addWriteFiles();
    _ = write_files_step.addCopyFile(m0plus_library.getEmittedBin(), "zip8/src/cortex-m0plus/libzip8.a");
    _ = write_files_step.addCopyFile(atmega4809_library_file, "zip8/src/atmega4809/libzip8.a");
    _ = write_files_step.addCopyFile(b.path("src/zip8.h"), "zip8/src/zip8.h");
    _ = write_files_step.addCopyFile(b.path("library.properties"), "zip8/library.properties");
    const zip_step = b.addSystemCommand(&.{ "sh", "-c", "cd $0; zip -r $1 zip8" });
    zip_step.addDirectoryArg(write_files_step.getDirectory());
    const zip_output = zip_step.addOutputFileArg("zip8.zip");
    const zip_install_step = b.addInstallFile(zip_output, "lib/zip8.zip");

    const arduino_step = b.step("arduino", "Build .zip Arduino library for ATmega4809 and Cortex-M0+ boards");
    arduino_step.dependOn(&zip_install_step.step);

    const m0plus_step = b.step("m0plus", "Output a static library for Cortex-M0+");
    m0plus_step.dependOn(&m0plus_library_install.step);

    const atmega4809_step = b.step("atmega4809", "Output a static library for ATmega4809");
    atmega4809_step.dependOn(&atmega4809_library_install.step);

    b.default_step.dependOn(&native_library_install.step);

    // Creates a step for unit testing.
    const exe_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe_tests.root_module.addImport("build_options", options_module);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    const test_run_cmd = b.addRunArtifact(exe_tests.step.cast(std.Build.Step.Compile).?);
    test_step.dependOn(&test_run_cmd.step);
}
