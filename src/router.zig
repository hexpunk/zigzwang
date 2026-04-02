const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

/// Terminals represent the end of a route and contain the handler and parameter names for that route.
fn Terminal(comptime T: type) type {
    return struct {
        const Self = @This();

        handler: T,
        parameter_names: ArrayList([]const u8) = .empty,

        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.parameter_names.deinit(allocator);
        }
    };
}

test "Terminal creation and deinitialization" {
    const TerminalType = Terminal(i32);
    var terminal = TerminalType{
        .handler = 42,
    };
    defer terminal.deinit(std.testing.allocator);

    try terminal.parameter_names.append(std.testing.allocator, "id");
    try terminal.parameter_names.append(std.testing.allocator, "name");

    try std.testing.expectEqual(42, terminal.handler);
    try std.testing.expectEqual(2, terminal.parameter_names.items.len);
    try std.testing.expectEqualStrings("id", terminal.parameter_names.items[0]);
    try std.testing.expectEqualStrings("name", terminal.parameter_names.items[1]);
}

/// Static segments match a specific path segment and can have child segments and/or be terminal.
const Static = struct {
    name: []const u8,
    children: ArrayList(usize) = .empty,
    terminal: ?usize = null,

    pub fn deinit(self: *Static, allocator: Allocator) void {
        self.children.deinit(allocator);
    }
};

test "Static segment creation and deinitialization" {
    var staticSegment = Static{
        .name = "users",
    };
    defer staticSegment.deinit(std.testing.allocator);

    try staticSegment.children.append(std.testing.allocator, 1);
    try staticSegment.children.append(std.testing.allocator, 2);
    staticSegment.terminal = 3;

    try std.testing.expectEqual("users", staticSegment.name);
    try std.testing.expectEqual(2, staticSegment.children.items.len);
    try std.testing.expectEqual(1, staticSegment.children.items[0]);
    try std.testing.expectEqual(2, staticSegment.children.items[1]);
    try std.testing.expectEqual(3, staticSegment.terminal.?);
}

/// Parameter segments match any single path segment and can have child segments and/or be terminal.
const Parameter = struct {
    children: ArrayList(usize) = .empty,
    terminal: ?usize = null,

    pub fn deinit(self: *Parameter, allocator: Allocator) void {
        self.children.deinit(allocator);
    }
};

test "Parameter segment creation and deinitialization" {
    var parameterSegment = Parameter{
        .terminal = 4,
    };
    defer parameterSegment.deinit(std.testing.allocator);

    try parameterSegment.children.append(std.testing.allocator, 5);
    try parameterSegment.children.append(std.testing.allocator, 6);

    try std.testing.expectEqual(2, parameterSegment.children.items.len);
    try std.testing.expectEqual(5, parameterSegment.children.items[0]);
    try std.testing.expectEqual(6, parameterSegment.children.items[1]);
    try std.testing.expectEqual(4, parameterSegment.terminal.?);
}

/// Wildcard segments match any remaining path segments and must be the last segment in a route.
const Wildcard = struct {
    terminal: usize,
};

test "Wildcard segment creation" {
    const wildcardSegment = Wildcard{
        .terminal = 7,
    };

    try std.testing.expectEqual(7, wildcardSegment.terminal);
}

const SegmentType = enum {
    static,
    parameter,
    wildcard,
};

const Segment = union(SegmentType) {
    static: Static,
    parameter: Parameter,
    wildcard: Wildcard,
};

fn Router(comptime T: type) type {
    return struct {
        const Self = @This();

        segments: ArrayList(Segment) = .empty,
        terminals: ArrayList(Terminal(T)) = .empty,

        pub fn deinit(self: *Self, allocator: Allocator) void {
            for (0..self.segments.items.len) |i| {
                switch (self.segments.items[i]) {
                    .static => self.segments.items[i].static.deinit(allocator),
                    .parameter => self.segments.items[i].parameter.deinit(allocator),
                    .wildcard => {},
                }
            }
            self.segments.deinit(allocator);

            for (0..self.terminals.items.len) |i| {
                self.terminals.items[i].deinit(allocator);
            }
            self.terminals.deinit(allocator);
        }
    };
}

test "Router creation and deinitialization" {
    const RouterType = Router(i32);
    var router = RouterType{};
    defer router.deinit(std.testing.allocator);

    var staticSegment = Static{
        .name = "users",
    };
    try staticSegment.children.append(std.testing.allocator, 1);
    try staticSegment.children.append(std.testing.allocator, 2);
    staticSegment.terminal = 3;

    var parameterSegment = Parameter{
        .terminal = 4,
    };
    try parameterSegment.children.append(std.testing.allocator, 5);
    try parameterSegment.children.append(std.testing.allocator, 6);

    const wildcardSegment = Wildcard{
        .terminal = 7,
    };
    try router.segments.append(std.testing.allocator, Segment{ .static = staticSegment });
    try router.segments.append(std.testing.allocator, Segment{ .parameter = parameterSegment });
    try router.segments.append(std.testing.allocator, Segment{ .wildcard = wildcardSegment });

    var terminal1 = Terminal(i32){
        .handler = 42,
    };
    try terminal1.parameter_names.append(std.testing.allocator, "id");
    try terminal1.parameter_names.append(std.testing.allocator, "name");

    var terminal2 = Terminal(i32){
        .handler = 43,
    };
    try terminal2.parameter_names.append(std.testing.allocator, "age");

    try router.terminals.append(std.testing.allocator, terminal1);
    try router.terminals.append(std.testing.allocator, terminal2);

    // Verify segments
    try std.testing.expectEqual(3, router.segments.items.len);
    try std.testing.expectEqual("users", router.segments.items[0].static.name);
    try std.testing.expectEqual(2, router.segments.items[0].static.children.items.len);
    try std.testing.expectEqual(1, router.segments.items[0].static.children.items[0]);
    try std.testing.expectEqual(2, router.segments.items[0].static.children.items[1]);
    try std.testing.expectEqual(3, router.segments.items[0].static.terminal.?);
    try std.testing.expectEqual(2, router.segments.items[1].parameter.children.items.len);
    try std.testing.expectEqual(4, router.segments.items[1].parameter.terminal.?);
    try std.testing.expectEqual(7, router.segments.items[2].wildcard.terminal);
}
