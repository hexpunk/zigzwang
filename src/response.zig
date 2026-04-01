const std = @import("std");
const Io = std.Io;
const StringHashMap = std.StringHashMap;

pub const Response = struct {
    _allocator: std.mem.Allocator,
    _sent: bool,

    headers: StringHashMap([]const u8),
    status_code: u16,
    body: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator) !Response {
        return .{
            ._allocator = allocator,
            ._sent = false,
            .status_code = 200,
            .headers = StringHashMap([]const u8).init(allocator),
            .body = null,
        };
    }

    pub fn send(self: *Response, io: Io) !void {
        if (self._sent) {
            return error.AlreadySent;
        }

        const buffer = try self._allocator.alloc(u8, 1024);
        defer self._allocator.free(buffer);

        var stdout = Io.File.Writer.init(Io.File.stdout(), io, buffer);
        const writer = &stdout.interface;

        try writer.print("Status: {d}\r\n", .{self.status_code});

        var it = self.headers.iterator();
        while (it.next()) |entry| {
            try writer.print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }

        try writer.print("Content-Length: {d}\r\n\r\n", .{if (self.body) |b| b.len else 0});
        if (self.body) |body| {
            try writer.writeAll(body);
        }
        try writer.flush();

        self._sent = true;
    }

    pub fn deinit(self: *Response) void {
        self.headers.deinit();
    }
};
