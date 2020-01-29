const std = @import("std");

pub fn build(bld: *std.build.Builder) void {
    const build_mode = bld.standardReleaseOptions();
    const demo = bld.addTest("demo.zig");
    demo.setBuildMode(build_mode);
    bld.default_step.dependOn(&demo.step);
}
