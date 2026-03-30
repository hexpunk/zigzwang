const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;

pub const Errors = error{
    MissingContentLength,
    MissingRequestMethod,
    BodyTooLarge,
};

pub const Request = struct {
    allocator: std.mem.Allocator,
    method: []const u8,
    path: []const u8,
    query_string: []const u8,
    headers: std.StringHashMap([]const u8),
    body: []const u8,

    pub fn init(io: Io, environ_map: *std.process.Environ.Map, allocator: Allocator, body_limit: Io.Limit) !Request {
        const content_length = environ_map.get("CONTENT_LENGTH") orelse "0";
        const body_length = try std.fmt.parseInt(u64, content_length, 10);

        if (body_limit.subtract(body_length) == null) {
            return Errors.BodyTooLarge;
        }

        var headers = StringHashMap([]const u8).init(allocator);
        errdefer headers.deinit();

        var it = environ_map.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;
            if (std.mem.startsWith(u8, key, "HTTP_")) {
                const header_name = try allocator.dupe(u8, key[5..]);
                const value_copy = try allocator.dupe(u8, value);

                try headers.put(header_name, value_copy);
            }
        }

        const body = try allocator.alloc(u8, body_length);
        errdefer allocator.free(body);

        var reader = Io.File.stdin().reader(io, body);
        try reader.interface.fill(body_length);

        const method = try allocator.dupe(u8, environ_map.get("REQUEST_METHOD") orelse return Errors.MissingRequestMethod);
        errdefer allocator.free(method);

        const path = try allocator.dupe(u8, environ_map.get("PATH_INFO") orelse "/");
        errdefer allocator.free(path);

        const query_string = try allocator.dupe(u8, environ_map.get("QUERY_STRING") orelse "");
        errdefer allocator.free(query_string);

        return .{
            .allocator = allocator,
            .method = method,
            .path = path,
            .query_string = query_string,
            .headers = headers,
            .body = body,
        };
    }

    pub fn deinit(self: *Request) void {
        self.allocator.free(self.body);
        self.headers.deinit();
        self.allocator.free(self.method);
        self.allocator.free(self.path);
        self.allocator.free(self.query_string);
    }
};

pub fn sendResponse(io: Io, allocator: Allocator, status_code: u16, headers: StringHashMap([]const u8), body: []const u8) !void {
    const buffer = try allocator.alloc(u8, 1024);
    defer allocator.free(buffer);

    var stdout = Io.File.Writer.init(Io.File.stdout(), io, buffer);
    const writer = &stdout.interface;

    try writer.print("Status: {d}\r\n", .{status_code});

    var it = headers.iterator();
    while (it.next()) |entry| {
        try writer.print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }

    try writer.print("Content-Length: {d}\r\n\r\n", .{body.len});
    try writer.writeAll(body);
    try writer.flush();
}
