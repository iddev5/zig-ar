const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;

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
    contents: []u8,
};

const Self = @This();

pub fn create(name: []const u8, allocator: *Allocator) !Self {
    var self = Self{
        .name = name,
        .fh = try std.fs.cwd().createFile(name, .{}),
        .allocator = allocator,
        .objects = std.ArrayList(ObjectFile).init(allocator),
    };

    return self;
}

pub fn open(name: []const u8, allocator: *Allocator) !Self {
    var self = Self{
        .name = name,
        .fh = try std.fs.cwd().openFile(name, .{ .write = true }),
        .allocator = allocator,
        .objects = std.ArrayList(ObjectFile).init(allocator),
    };

    try self.parse();

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

    const name = try mem.concat(self.allocator, u8, &.{ file_name, "/" });
    defer self.allocator.free(name);

    var buf = [_]u8{0} ** @sizeOf(Header);
    _ = try std.fmt.bufPrint(
        &buf,
        "{s: <16}{: <12}{: <6}{: <6}{o: <8}{: <10}`\n",
        .{ name, 0, 0, 0, stat.mode, stat.size },
    );

    const object = ObjectFile{
        .header = @ptrCast(*Header, &buf).*,
        .contents = data,
    };

    try self.objects.append(object);
}

pub fn deleteMod(self: *Self, file_name: []const u8) !void {
    for (self.objects.items) |item, index| {
        if (std.mem.eql(u8, std.mem.trim(u8, &item.header.name, " /"), file_name)) {
            _ = self.objects.orderedRemove(index);
            break;
        }
    }
}

pub fn finalize(self: *Self) !void {
    try self.fh.seekTo(0);

    const writer = self.fh.writer();
    try writer.writeAll("!<arch>\n");

    for (self.objects.items) |item| {
        try writer.writeStruct(item.header);
        try writer.writeAll(item.contents);
    }

    try self.fh.setEndPos(try self.fh.getPos());
}

fn parse(self: *Self) !void {
    var reader = self.fh.reader();

    var magic = try reader.readBytesNoEof(8);
    if (!std.mem.eql(u8, &magic, "!<arch>\n"))
        return error.InvalidArchive;

    while (true) {
        var obj_file: ObjectFile = undefined;
        obj_file.header = reader.readStruct(Header) catch |err| switch (err) {
            error.EndOfStream => break,
            else => |e| return e,
        };

        const size = try std.fmt.parseUnsigned(u32, std.mem.trimRight(u8, &obj_file.header.size, " "), 10);
        obj_file.contents = try self.allocator.alloc(u8, size);
        try reader.readNoEof(obj_file.contents);

        try self.objects.append(obj_file);
    }
}

pub fn print(self: *Self, name: []const u8, writer: std.fs.File.Writer) !void {
    for (self.objects.items) |item| {
        if (std.mem.eql(u8, std.mem.trim(u8, &item.header.name, " /"), name)) {
            try writer.print("{s}", .{item.contents});
            break;
        }
    }
}
