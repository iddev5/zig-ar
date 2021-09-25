const std = @import("std");
const Allocator = std.mem.Allocator;

const Archive = struct {
    name: []const u8,
    fh: std.fs.File,
    allocator: *Allocator,

    const Header = packed struct {
        name: [16]u8,
        mtime: [12]u8,
        ownerid: [6]u8,
        groupid: [6]u8,
        mode: [8]u8,
        size: [10]u8,
    };
    
    const ObjectFile = struct {
        header: Header,
        contents: ?[]const u8,
    };

    const Self = @This();

    pub fn create(name: []const u8, allocator: *Allocator) !Self {
        var self = Self{
            .name = name,
            .fh = try std.fs.cwd().createFile(name, .{}),
            .allocator = allocator,
        };

        try self.fh.writeAll("!<arch>\n");

        return self;
    }

    pub fn open(name: []const u8, allocator: *Allocator) !Self {
        var self = Self{
            .name = name,
            .fh = try std.fs.cwd().openFile(name, .{}),
            .allocator = allocator,
        };
        
        try self.read();
        
        return self;
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
        try writer.writeByteNTimes(' ', 15 - file_name.len);
        try writer.print("{: <12}{: <6}{: <6}{o: <8}{: <10}`\n", .{ 0, 0, 0, stat.mode, stat.size });
        try writer.writeAll(data);
    }
    
    fn read(self: *Self) !void {
        var reader = self.fh.reader();
        
        var magic = try reader.readBytesNoEof(8);
        if (!std.mem.eql(u8, &magic, "!<arch>\n"))
            return error.InvalidArchive;
        
        var is_eof = false;    
        while (!is_eof) {
            var obj_file: ObjectFile = undefined;
            obj_file.header = reader.readStruct(Header) catch |err| switch (err) {
                error.EndOfStream => break,
                else => |e| return e,
            };
        
            const name = std.mem.trimRight(u8, obj_file.header.name[0..], " /");
            std.debug.print("name: {s}\n", .{name});
        }
    }
};

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = &gpa.allocator;

    const args = try std.process.argsAlloc(allocator);
    defer allocator.free(args);

    // var file = try Archive.create(args[1], allocator);

    // for (args[2..]) |file_name| {
    //     try file.writeFile(file_name);
    // }
    
    var file = try Archive.open(args[1], allocator);
    defer file.close();
}
