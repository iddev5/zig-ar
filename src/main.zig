const std = @import("std");
const Allocator = std.mem.Allocator;

const Archive = struct {
    name: []const u8,
    fh: std.fs.File,
    allocator: *Allocator,

    const Header = struct {
        name: [16]u8,
        mtime: [12]u8,
        ownerid: [6]u8,
        groupid: [6]u8,
        mode: [8]u8,
        size: [10]u8,
    };

    const Self = @This();

    pub fn create(name: []const u8, allocator: *Allocator) !Self {
        const self = Self{
            .name = name,
            .fh = try std.fs.cwd().createFile(name, .{}),
            .allocator = allocator,
        };

        try self.fh.writeAll("!<arch>\n");

        return self;
    }

    pub fn open(name: []const u8, allocator: *Allocator) !Self {
        return .{
            .name = name,
            .fh = try std.fs.cwd().openFile(name, .{}),
            .allocator = allocator,
        };
    }

    pub fn close(self: *Self) void {
        self.fh.close();
    }

    pub fn writeFile(self: *Self, file_name: []const u8) !void {
        const obj_file = try std.fs.cwd().openFile(file_name, .{ .read = true });
        defer obj_file.close();

        const data = try obj_file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(data);

        var stat = try obj_file.stat();

        var writer = self.fh.writer();
        try writer.writeAll(file_name);
        try writer.writeAll("/");
        try writer.writeByteNTimes(' ', 16 - file_name.len + 1);
        try writer.print("{: <10}{: <6}{: <6}{o: <8}{: <10}`\n", .{ 0, 0, 0, stat.mode, stat.size });
        try writer.writeAll(data);
    }
};

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = &gpa.allocator;

    const args = try std.process.argsAlloc(allocator);
    defer allocator.free(args);

    var file = try Archive.create(args[1], allocator);

    for (args[2..]) |file_name| {
        try file.writeFile(file_name);
    }
}
