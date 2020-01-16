const std = @import("std");

const Builder = @import("std").build.Builder;

pub fn build(bld: *Builder) void {
    const mode = bld.standardReleaseOptions();

    const prog_atem = bld.addExecutable("zatem", "cmd/atem/main.zig");
    if (std.os.getenv("USER")) |username|
        if (std.mem.eql(u8, username, "_"))
            prog_atem.setOutputDir("/home/_/b/");
    prog_atem.setBuildMode(mode);
    prog_atem.addPackagePath("atem", "src/atem.zig");
    prog_atem.install();

    const run_cmd = prog_atem.run();
    run_cmd.step.dependOn(bld.getInstallStep());
    addArgs(run_cmd);
    const run_step = bld.step("run", "Run the app, use -- for passing args");
    run_step.dependOn(&run_cmd.step);
}

fn addArgs(run: *std.build.RunStep) void {
    var i: usize = 0;
    var ok = false;
    while (i < std.os.argv.len) : (i += 1) {
        const argval = std.mem.toSlice(u8, std.os.argv[i]);
        if (ok)
            run.addArg(argval)
        else
            ok = std.mem.eql(u8, argval, "--");
    }
}
