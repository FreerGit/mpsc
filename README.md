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

## Future Work
I'd love to have optionality for static allocation, however im not sure how to complete that at this moment and for my purposes, using a heap is OK for now. 
If your hot path can not have mallocs, then this lib may not be for you.
