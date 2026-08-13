const std = @import("std");

// i may need to remove them tests later cuz our shit works 
// do not recommend building with release, as this is mostly io stuff and moving files, so making the binary smaller is the better choice
pub fn build(b: *std.Build) void {
    const release = b.option(bool, "release", "strip debug + optimize") orelse false;
    const small = b.option(bool, "small", "strip debug + make binary smaller") orelse false;
   
    const linux = b.option(bool, "linux", "cross compile to linux based systems") orelse false;

    
    const target = if (linux) // also on arg
    b.resolveTargetQuery(.{
        .cpu_arch = .x86_64, // for linux
        .os_tag = .linux,
    })
    else
    b.standardTargetOptions(.{});
    
    const utils = b.createModule(.{
        .root_source_file = b.path("src/utils/utils.zig"),
    });

    const parser = b.createModule(.{
        .root_source_file = b.path("src/parsers/parsers.zig"),
    });

 
    const exe = b.addExecutable(.{
        .name = "xpk",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .strip = release or small,
            .optimize = if (release) .ReleaseFast else if (small) .ReleaseSmall else .Debug,
        }),
    });



    const hasher = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/security/hasher_test.zig"),
            .target = target,
            .optimize = if (release) .ReleaseFast else if (small) .ReleaseSmall else .Debug,
        })
    });

    const parsers = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/parsers/parsers_test.zig"),
            .target = target,
            .optimize = if (release) .ReleaseFast else if (small) .ReleaseSmall else .Debug,
        })
    });
    
    
    const automl = b.dependency("automl", .{
        .target = target,
    });
    
   
    const hashertests = b.addRunArtifact(hasher);
    const parsertests = b.addRunArtifact(parsers);
    const tests = b.step("test", "run parser tests"); // an arg
    tests.dependOn(&hashertests.step);
    tests.dependOn(&parsertests.step);
  
    
    parser.addImport("automl", automl.module("automl"));
    parsers.root_module.addImport("automl", automl.module("automl"));
    exe.root_module.addImport("automl", automl.module("automl"));
    exe.root_module.addImport("utils", utils);
    b.installArtifact(exe);
}