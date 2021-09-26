const std = @import("std");
const Archive = @import("Archive.zig");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = &gpa.allocator;

    const args = try std.process.argsAlloc(allocator);
    defer allocator.free(args);

    const stdout = std.io.getStdOut().writer();

    if (std.mem.eql(u8, args[1], "r")) {
        var file = try Archive.create(args[2], allocator);
        defer file.close();

        try file.addMod(args[3..]);
        try file.finalize();
    } else if (std.mem.eql(u8, args[1], "d")) {
        var file = try Archive.open(args[2], allocator);
        defer file.close();

        try file.deleteMod(args[3..]);
        try file.finalize();
    } else if (std.mem.eql(u8, args[1], "p")) {
        var file = try Archive.open(args[2], allocator);
        defer file.close();

        if (args.len > 3) {
            try file.print(&.{args[3]}, stdout);
        } else {
            try file.print(null, stdout);
        }
    } else if (std.mem.eql(u8, args[1], "x")) {
        var file = try Archive.open(args[2], allocator);
        defer file.close();

        if (args.len > 3) {
            try file.extract(&.{args[3]});
        } else {
            try file.extract(null);
        }

    }
}
