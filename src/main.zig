const std = @import("std");
const StringHashMap = std.StringHashMap;

const sqlite = @import("sqlite.zig");
const Request = @import("request.zig").Request;
const Response = @import("response.zig").Response;

pub fn main(init: std.process.Init) !void {
    const db_path = init.environ_map.get("SQLITE_DB_PATH") orelse return error.MissingDatabasePath;
    std.debug.print("DEBUG: Opening database at: {s}\n", .{db_path});
    var db = try sqlite.SqliteDatabase.init(db_path);
    defer db.close();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var response_headers = StringHashMap([]const u8).init(allocator);
    defer response_headers.deinit();

    try response_headers.put("Content-Type", "text/html");

    var request = Request.init(init.io, init.environ_map, allocator, .unlimited);
    var response = try Response.init(allocator);
    defer response.deinit();

    if (request) |*req| {
        defer req.deinit();

        const msg = try std.fmt.allocPrint(allocator, "<html><body><h1>Hello, world! from {s}</h1></body></html>", .{req.path});
        defer allocator.free(msg);
        response.body = msg;

        try response.send(init.io);
    } else |err| {
        const msg = try std.fmt.allocPrint(allocator, "<html><body><h1>Bad Request: {s}</h1></body></html>", .{@errorName(err)});
        defer allocator.free(msg);

        response.status_code = 400;
        response.body = msg;

        try response.send(init.io);
    }
}

test {
    std.testing.refAllDecls(@This());
}
