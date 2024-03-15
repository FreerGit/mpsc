# mpsc
A wait-free Multi Producer Single Consumer (MPSC) queue

## Install
1. Declare Money as a dependecy:
```console
zig fetch --save git+https://github.com/freergit/mpsc.git#main
```

2. Expose Money as a module in build.zig:
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mpsc_dep = b.dependency("mpsc", .{ .target = target, .optimize = optimize });
    const mpsc_module = mpsc_dep.module("mpsc");

    const exe = b.addExecutable(.{
        .name = "my-project",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("mpsc", mpsc_module);
    
    // ...
}
```

Of course, you can use simply download the repo (git subtree, or similar) and build it instead of using the package manager.