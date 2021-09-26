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
    
        for (args[3..]) |file_name| {
            try file.addMod(file_name);
        }
        
        try file.finalize();
    }
    else {
        var file = try Archive.open(args[2], allocator);
        try file.print(args[3], stdout);
        defer file.close();
    }
}
