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

    const static = b.addModule("staticlib", .{
        .link_libc = true,
        .optimize = optimize,
        .target = target,
    });
    static.addCSourceFiles(.{
        .root = lua_src.path("src"),
        .files = &base_src,
        .flags = &cflags,
    });

    const shared = b.addModule("sharedlib", .{
        .link_libc = true,
        .optimize = optimize,
        .target = target,
        .strip = if (target.result.os.tag == .windows) true else null,
    });
    shared.addCSourceFiles(.{
        .root = lua_src.path("src"),
        .files = &base_src,
        .flags = &cflags,
    });

    const exe = b.addModule("interpreter", .{
        .link_libc = true,
        .optimize = optimize,
        .target = target,
    });
    exe.addCSourceFile(.{
        .file = lua_src.path("src/lua.c"),
        .flags = &cflags,
    });

    const exec = b.addModule("compiler", .{
        .link_libc = true,
        .optimize = optimize,
        .target = target,
    });
    exec.addCSourceFile(.{
        .file = lua_src.path("src/luac.c"),
        .flags = &cflags,
    });

    // Common compile flags
    for (&[_]*Build.Module{ static, shared, exe, exec }) |mod| {
        const link = mod != shared;

        mod.addIncludePath(lua_src.path("src"));
        if (link and !target.result.isMinGW())
            mod.linkSystemLibrary("m", .{});

        switch (target.result.os.tag) {
            .aix => {
                mod.addCMacro("LUA_USE_POSIX", "");
                mod.addCMacro("LUA_USE_DLOPEN", "");
                if (link)
                    mod.linkSystemLibrary("dl", .{});
            },
            .freebsd, .netbsd, .openbsd => {
                mod.addCMacro("LUA_USE_LINUX", "");
                mod.addCMacro("LUA_USE_READLINE", "");
                mod.addIncludePath(.{ .cwd_relative = "/usr/include/edit" });
                if (link)
                    mod.linkSystemLibrary("edit", .{});
            },
            .ios => {
                mod.addCMacro("LUA_USE_IOS", "");
            },
            .linux => {
                mod.addCMacro("LUA_USE_LINUX", "");
                if (link)
                    mod.linkSystemLibrary("dl", .{});
                if (use_readline.?) {
                    mod.addCMacro("LUA_USE_READLINE", "");
                    if (link)
                        mod.linkSystemLibrary("readline", .{});
                }
            },
            .macos => {
                mod.addCMacro("LUA_USE_MACOSX", "");
                mod.addCMacro("LUA_USE_READLINE", "");
                if (link)
                    mod.linkSystemLibrary("readline", .{});
            },
            .solaris => {
                mod.addCMacro("LUA_USE_POSIX", "");
                mod.addCMacro("LUA_USE_DLOPEN", "");
                mod.addCMacro("_REENTRANT", "");
                if (link)
                    mod.linkSystemLibrary("dl", .{});
            },
            else => {},
        }
    }
    if (target.result.isMinGW()) {
        static.addCMacro("LUA_BUILD_AS_DLL", "");
        exe.addCMacro("LUA_BUILD_AS_DLL", "");
    }

    const sharedlib = b.addLibrary(.{
        .name = "lua" ++ &[_]u8{
            '0' + version.major, '0' + version.minor,
        },
        .root_module = shared,
        .version = version,
        .linkage = .dynamic,
    });
    b.installArtifact(sharedlib);

    const staticlib =
        b.addLibrary(.{
            .name = "lua",
            .root_module = static,
            .version = version,
            .linkage = .static,
        });
    b.installArtifact(staticlib);

    exe.linkLibrary(if (build_shared) sharedlib else staticlib);
    const lua_exe = b.addExecutable(.{
        .name = "lua_exe",
        .version = version,
        .root_module = exe,
    });
    b.installArtifact(lua_exe);

    exec.linkLibrary(staticlib);
    const luac_exe = b.addExecutable(.{
        .name = "luac",
        .version = version,
        .root_module = exe,
    });
    b.installArtifact(luac_exe);

    b.installDirectory(.{
        .source_dir = lua_src.path("doc"),
        .include_extensions = &.{".1"},
        .install_dir = .{ .custom = "man" },
        .install_subdir = "man1",
    });

    const run_step = b.step("run", "run lua interpreter");
    const run_cmd = b.addRunArtifact(lua_exe);
    if (b.args) |args| run_cmd.addArgs(args);
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
