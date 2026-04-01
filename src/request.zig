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
    _allocator: std.mem.Allocator,

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
            ._allocator = allocator,
            .method = method,
            .path = path,
            .query_string = query_string,
            .headers = headers,
            .body = body,
        };
    }

    pub fn deinit(self: *Request) void {
        self._allocator.free(self.body);
        self.headers.deinit();
        self._allocator.free(self.method);
        self._allocator.free(self.path);
        self._allocator.free(self.query_string);
    }
};
