const std = @import("std");
const Build = std.Build;
const StringList = std.ArrayList([]const u8);
const ResolvedTarget = Build.ResolvedTarget;
const OptimizeMode = std.builtin.OptimizeMode;
const version = std.SemanticVersion{
    .major = 5,
    .minor = 4,
    .patch = 8,
};
const lib_name = "lua";
const exe_name = lib_name ++ "_exe";
const compiler_name = "luac";

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    const build_shared = b.option(bool, "shared", "build as shared library") orelse target.result.isMinGW();
    const use_readline =
        if (target.result.os.tag == .linux)
            b.option(bool, "use_readline", "readline support for linux") orelse false
        else
            null;

    const lua_src = b.dependency("lua", .{});

    const lib = b.addLibrary(.{
        .name = lib_name,
        .linkage = .static,
        .root_module = b.createModule(.{
            .link_libc = true,
            .optimize = optimize,
            .target = target,
        }),
    });
    const shared = if (build_shared)
        b.addLibrary(.{
            .name = lib_name ++ "54",
            .linkage = .dynamic,
            .root_module = b.createModule(.{
                .link_libc = true,
                .optimize = optimize,
                .target = target,
                .strip = if (target.result.os.tag == .windows) true else null,
            }),
        })
    else
        null;
    const exe = b.addExecutable(.{
        .name = exe_name,
        .root_module = b.createModule(.{
            .link_libc = true,
            .optimize = optimize,
            .target = target,
        }),
    });
    const exec = b.addExecutable(.{
        .name = compiler_name,
        .root_module = b.createModule(.{
            .link_libc = true,
            .optimize = optimize,
            .target = target,
        }),
    });
    if (!target.result.isMinGW()) {
        lib.linkSystemLibrary("m");
        exe.linkSystemLibrary("m");
        exec.linkSystemLibrary("m");
    }
    const build_targets = [_]?*Build.Step.Compile{
        lib,
        exe,
        exec,
        shared,
    };
    // Common compile flags
    for (&build_targets) |tr| {
        if (tr == null)
            continue;
        const t = tr.?;
        t.linkLibC();
        t.addIncludePath(lua_src.path("src"));
        switch (target.result.os.tag) {
            .aix => {
                t.root_module.addCMacro("LUA_USE_POSIX", "");
                t.root_module.addCMacro("LUA_USE_DLOPEN", "");
                t.linkSystemLibrary("dl");
            },
            .freebsd, .netbsd, .openbsd => {
                t.root_module.addCMacro("LUA_USE_LINUX", "");
                t.root_module.addCMacro("LUA_USE_READLINE", "");
                t.addIncludePath(.{ .cwd_relative = "/usr/include/edit" });
                t.linkSystemLibrary("edit");
            },
            .ios => {
                t.root_module.addCMacro("LUA_USE_IOS", "");
            },
            .linux => {
                t.root_module.addCMacro("LUA_USE_LINUX", "");
                t.linkSystemLibrary("dl");
                if (use_readline.?) {
                    t.root_module.addCMacro("LUA_USE_READLINE", "");
                    t.linkSystemLibrary("readline");
                }
            },
            .macos => {
                t.root_module.addCMacro("LUA_USE_MACOSX", "");
                t.root_module.addCMacro("LUA_USE_READLINE", "");
                t.linkSystemLibrary("readline");
            },
            .solaris => {
                t.root_module.addCMacro("LUA_USE_POSIX", "");
                t.root_module.addCMacro("LUA_USE_DLOPEN", "");
                t.root_module.addCMacro("_REENTRANT", "");
                t.linkSystemLibrary("dl");
            },
            else => {},
        }
    }
    if (target.result.isMinGW()) {
        lib.root_module.addCMacro("LUA_BUILD_AS_DLL", "");
        exe.root_module.addCMacro("LUA_BUILD_AS_DLL", "");
    }
    if (shared) |s| {
        s.addCSourceFiles(.{
            .root = lua_src.path("src"),
            .files = &base_src,
            .flags = &cflags,
        });

        s.installHeadersDirectory(
            lua_src.path("src"),
            "",
            .{ .include_extensions = &lua_inc },
        );
    }

    lib.addCSourceFiles(.{
        .root = lua_src.path("src"),
        .files = &base_src,
        .flags = &cflags,
    });

    lib.installHeadersDirectory(
        lua_src.path("src"),
        "",
        .{ .include_extensions = &lua_inc },
    );

    exe.addCSourceFile(.{
        .file = lua_src.path("src/lua.c"),
        .flags = &cflags,
    });

    exec.addCSourceFile(.{
        .file = lua_src.path("src/luac.c"),
        .flags = &cflags,
    });

    if (shared) |s| {
        exe.linkLibrary(s);
        b.installArtifact(s);
    } else {
        exe.linkLibrary(lib);
        b.installArtifact(lib);
    }

    b.installArtifact(exe);
    exec.linkLibrary(lib);
    b.installArtifact(exec);

    b.installDirectory(.{
        .source_dir = lua_src.path("doc"),
        .include_extensions = &.{".1"},
        .install_dir = .{ .custom = "man" },
        .install_subdir = "man1",
    });

    const run_step = b.step("run", "run lua interpreter");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    const unpack_step = b.step("unpack", "unpack source");
    const unpack_cmd = b.addInstallDirectory(.{
        .source_dir = lua_src.path(""),
        .install_dir = .prefix,
        .install_subdir = "",
    });
    unpack_step.dependOn(&unpack_cmd.step);
}

const cflags = [_][]const u8{
    "-std=gnu99",
    "-Wall",
    "-Wextra",
};

const core_src = [_][]const u8{
    "lapi.c",
    "lcode.c",
    "lctype.c",
    "ldebug.c",
    "ldo.c",
    "ldump.c",
    "lfunc.c",
    "lgc.c",
    "llex.c",
    "lmem.c",
    "lobject.c",
    "lopcodes.c",
    "lparser.c",
    "lstate.c",
    "lstring.c",
    "ltable.c",
    "ltm.c",
    "lundump.c",
    "lvm.c",
    "lzio.c",
};
const lib_src = [_][]const u8{
    "lauxlib.c",
    "lbaselib.c",
    "lcorolib.c",
    "ldblib.c",
    "liolib.c",
    "lmathlib.c",
    "loadlib.c",
    "loslib.c",
    "lstrlib.c",
    "ltablib.c",
    "lutf8lib.c",
    "linit.c",
};
const base_src = core_src ++ lib_src;

const lua_inc = [_][]const u8{
    "lua.h",
    "luaconf.h",
    "lualib.h",
    "lauxlib.h",
    "lua.hpp",
};
