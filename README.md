# Lua 
## 5.4.7

## Warning
due to a bug in the 0.13.0 release of the zig compiler you will need the development version of zig in order to build the lua54.dll on windows.

## Build Instructions
To build all targets run 
```sh
zig build
```

## Build Artifacts
| Name      | Artifact                  |
|:---------:| ------------------------- |
| "lua"     | The main lua library      |
| "lua_exe" | The lua interpreter       |
| "luac"    | The lua bytecode compiler |

## Compile Options
| Name         | Type | Description                |
|:------------:| ---- | -------------------------- |
| release      | bool | optimize for end users     |
| shared       | bool | build as shared library    |
| use_readline | bool | readline support for linux |

## Using in a zig project
To add to a zig project run:
```
zig fetch --save https://github.com/allyourcodebase/lua/archive/refs/tags/5.4.7.tar.gz
```
then add the following to your `build.zig` 
```zig
const lua_dep = b.dependency("lua", .{
    .target = target,
    .release = optimize != .Debug,
});
const lua_lib = lua_dep.artifact("lua");
```
