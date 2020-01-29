const std = @import("std");

pub fn build(bld: *std.build.Builder) void {
    const mode = bld.standardReleaseOptions();

    const dirname = std.fs.path.basename(bld.build_root);
    const prog = bld.addExecutable(dirname, "main.zig");
    prog.setBuildMode(mode);
    // prog.addPackagePath("lib", "path/to/lib.zig");
    if (std.os.getenv("USER")) |username|
        if (std.mem.eql(u8, username, "_")) // only locally at my end:
            prog.setOutputDir("/home/_/b/"); // place binary into in-PATH bin dir
    prog.install();

    const run_cmd = prog.run();
    if (bld.args) |args|
        run_cmd.addArgs(args);
    run_cmd.step.dependOn(bld.getInstallStep());
    const run_step = bld.step("run", "Run the program, use -- for passing args");
    run_step.dependOn(&run_cmd.step);
}
