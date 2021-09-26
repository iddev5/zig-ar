const std = @import("std");
const Allocator = std.mem.Allocator;

const Archive = struct {
    name: []const u8,
    fh: std.fs.File,
    allocator: *Allocator,
    objects: std.ArrayList(ObjectFile),

    const Header = extern struct {
        name: [16]u8,
        mtime: [12]u8,
        ownerid: [6]u8,
        groupid: [6]u8,
        mode: [8]u8,
        size: [10]u8,
        end: [2]u8,
    };

    const ObjectFile = struct {
        header: Header,
        contents: []const u8,
    };

    const Self = @This();

    pub fn create(name: []const u8, allocator: *Allocator) !Self {
        var self = Self{
            .name = name,
            .fh = try std.fs.cwd().createFile(name, .{}),
            .allocator = allocator,
            .objects = std.ArrayList(ObjectFile).init(allocator),
        };

        try self.fh.writeAll("!<arch>\n");

        return self;
    }

    pub fn open(name: []const u8, allocator: *Allocator) !Self {
        var self = Self{
            .name = name,
            .fh = try std.fs.cwd().openFile(name, .{}),
            .allocator = allocator,
            .objects = std.ArrayList(ObjectFile).init(allocator),
        };

        try self.read();

        return self;
    }

    pub fn close(self: *Self) void {
        for (self.objects.items) |item| {
            self.allocator.free(item.contents);
        }
    
        self.objects.deinit();
        self.fh.close();
    }

    pub fn addMod(self: *Self, file_name: []const u8) !void {
        const obj_file = try std.fs.cwd().openFile(file_name, .{ .read = true });
        defer obj_file.close();

        const data = try obj_file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        const stat = try obj_file.stat();

        const name = try std.mem.concat(self.allocator, u8, &.{ file_name, "/" });
        defer self.allocator.free(name);

        var buf = [_]u8{0} ** @sizeOf(Header);
        _ = try std.fmt.bufPrint(&buf, "{s: <16}{: <12}{: <6}{: <6}{o: <8}{: <10}`\n", .{ name, 0, 0, 0, stat.mode, stat.size },);
        
        const object = ObjectFile{
            .header = @ptrCast(*Header, &buf).*,
            .contents = data,
        };
        
        try self.objects.append(object);
    }
    
    pub fn finalize(self: *Self) !void {
        const writer = self.fh.writer();
        for (self.objects.items) |item| {
            try writer.writeStruct(item.header);
            try writer.writeAll(item.contents);
        }
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
        defer file.close();
    }
}
