const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addExecutable(.{
        .name = "typst_sqlite_zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Export as WASM library (no entry point)
    lib.entry = .disabled;
    lib.root_module.red_zone = false;

    // Export memory so Typst can access it
    lib.export_memory = true;
    // Keep exported symbols (don't strip @export'd functions)
    lib.rdynamic = true;

    // Compile SQLite as C dependency
    lib.root_module.addCSourceFile(.{
        .file = b.path("sqlite3.c"),
        .flags = &.{
            "-DSQLITE_OMIT_LOAD_EXTENSION",
            "-DSQLITE_THREADSAFE=0",
            "-DSQLITE_OMIT_LOCALTIME",
            "-DSQLITE_OMIT_AUTOINIT",
            "-DSQLITE_OMIT_UTF16",
            "-DSQLITE_OMIT_DEPRECATED",
            "-DSQLITE_OMIT_PROGRESS_CALLBACK",
            "-DSQLITE_OMIT_SHARED_CACHE",
            "-DSQLITE_DEFAULT_MEMSTATUS=0",
            "-DSQLITE_DQS=0",
            "-DSQLITE_OS_OTHER=1",
            "-DSQLITE_ENABLE_MEMSYS5",
            "-DSQLITE_OMIT_WAL",
            "-DSQLITE_OMIT_COMPLETE",
            "-DSQLITE_OMIT_TRACE",
            "-DSQLITE_OMIT_AUTHORIZATION",
            "-DSQLITE_OMIT_DESERIALIZE",
            "-DSQLITE_OMIT_GET_TABLE",
            "-DSQLITE_TEMP_STORE=3",
            "-fno-stack-protector",
            "-fno-sanitize=undefined",
        },
    });

    // Compile libc stubs
    lib.root_module.addCSourceFile(.{
        .file = b.path("libc-stubs/libc.c"),
        .flags = &.{
            "-fno-stack-protector",
            "-fno-sanitize=undefined",
        },
    });

    // SQLite headers first (so sqlite3.h is found)
    lib.root_module.addIncludePath(b.path("."));
    // Minimal libc stubs (stdio.h, stdlib.h, etc.)
    lib.root_module.addSystemIncludePath(b.path("libc-stubs"));

    b.installArtifact(lib);
}
