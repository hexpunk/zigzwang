const std = @import("std");
const StringHashMap = std.StringHashMap;

const sqlite = @import("sqlite.zig");
const cgi = @import("cgi.zig");

pub fn main(init: std.process.Init) !void {
    var db = try sqlite.SqliteDatabase.init("test.db");
    defer db.close();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var response_headers = StringHashMap([]const u8).init(allocator);
    defer response_headers.deinit();

    try response_headers.put("Content-Type", "text/html");

    var request = cgi.Request.init(init.io, init.environ_map, allocator, .unlimited);

    if (request) |*req| {
        defer req.deinit();

        const msg = try std.fmt.allocPrint(allocator, "<html><body><h1>Hello, world! from {s}</h1></body></html>", .{req.path});
        defer allocator.free(msg);

        try cgi.sendResponse(init.io, allocator, 200, response_headers, msg);
    } else |err| {
        const msg = try std.fmt.allocPrint(allocator, "<html><body><h1>Bad Request: {s}</h1></body></html>", .{@errorName(err)});
        defer allocator.free(msg);

        try cgi.sendResponse(init.io, allocator, 400, response_headers, msg);
    }
}

test {
    std.testing.refAllDecls(@This());
}
