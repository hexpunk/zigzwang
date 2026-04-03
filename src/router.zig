const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

/// Terminals represent the end of a route and contain the handler and parameter names for that route.
fn Terminal(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        handler: T,
        parameter_names: ArrayList([]const u8) = .empty,

        pub fn deinit(self: *Self) void {
            self.parameter_names.deinit(self.allocator);
        }
    };
}

test "Terminal creation and deinitialization" {
    const TerminalType = Terminal(i32);
    var terminal = TerminalType{
        .allocator = std.testing.allocator,
        .handler = 42,
    };
    defer terminal.deinit();

    try terminal.parameter_names.append(std.testing.allocator, "id");
    try terminal.parameter_names.append(std.testing.allocator, "name");

    try std.testing.expectEqual(42, terminal.handler);
    try std.testing.expectEqual(2, terminal.parameter_names.items.len);
    try std.testing.expectEqualStrings("id", terminal.parameter_names.items[0]);
    try std.testing.expectEqualStrings("name", terminal.parameter_names.items[1]);
}

/// Static segments match a specific path segment and can have child segments and/or be terminal.
const Static = struct {
    allocator: Allocator,

    name: []const u8,
    children: ArrayList(usize) = .empty,
    terminal: ?usize = null,

    pub fn init(allocator: Allocator, name: []const u8) Static {
        return Static{
            .allocator = allocator,
            .name = name,
            .children = .empty,
            .terminal = null,
        };
    }

    pub fn addChild(self: *Static, childIndex: usize) !void {
        try self.children.append(self.allocator, childIndex);
    }

    pub fn deinit(self: *Static) void {
        self.children.deinit(self.allocator);
    }
};

test "Static segment creation and deinitialization" {
    var staticSegment = Static.init(std.testing.allocator, "users");
    defer staticSegment.deinit();

    try staticSegment.addChild(1);
    try staticSegment.addChild(2);
    staticSegment.terminal = 3;

    try std.testing.expectEqual("users", staticSegment.name);
    try std.testing.expectEqual(2, staticSegment.children.items.len);
    try std.testing.expectEqual(1, staticSegment.children.items[0]);
    try std.testing.expectEqual(2, staticSegment.children.items[1]);
    try std.testing.expectEqual(3, staticSegment.terminal.?);
}

/// Parameter segments match any single path segment and can have child segments and/or be terminal.
const Parameter = struct {
    allocator: Allocator,

    children: ArrayList(usize) = .empty,
    terminal: ?usize = null,

    pub fn init(allocator: Allocator) Parameter {
        return Parameter{
            .allocator = allocator,
            .children = .empty,
            .terminal = null,
        };
    }

    pub fn addChild(self: *Parameter, childIndex: usize) !void {
        try self.children.append(self.allocator, childIndex);
    }

    pub fn deinit(self: *Parameter) void {
        self.children.deinit(self.allocator);
    }
};

test "Parameter segment creation and deinitialization" {
    var parameterSegment = Parameter.init(std.testing.allocator);
    defer parameterSegment.deinit();

    parameterSegment.terminal = 4;

    try parameterSegment.addChild(5);
    try parameterSegment.addChild(6);

    try std.testing.expectEqual(2, parameterSegment.children.items.len);
    try std.testing.expectEqual(5, parameterSegment.children.items[0]);
    try std.testing.expectEqual(6, parameterSegment.children.items[1]);
    try std.testing.expectEqual(4, parameterSegment.terminal);
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
        allocator: Allocator,

        segments: ArrayList(Segment) = .empty,
        terminals: ArrayList(Terminal(T)) = .empty,

        pub fn init(allocator: Allocator) Self {
            return Self{
                .allocator = allocator,
                .segments = .empty,
                .terminals = .empty,
            };
        }

        pub fn addStatic(self: *Self, name: []const u8) !usize {
            const segment = Static{
                .allocator = self.allocator,
                .name = name,
            };
            const index = self.segments.items.len;

            try self.segments.append(self.allocator, Segment{ .static = segment });

            return index;
        }

        pub fn addParameter(self: *Self) !usize {
            const segment = Parameter{
                .allocator = self.allocator,
            };
            const index = self.segments.items.len;

            try self.segments.append(self.allocator, Segment{ .parameter = segment });

            return index;
        }

        pub fn addWildcard(self: *Self) !usize {
            const segment = Wildcard{};
            const index = self.segments.items.len;

            try self.segments.append(self.allocator, Segment{ .wildcard = segment });

            return index;
        }

        pub fn addTerminal(self: *Self, handler: T, parameter_names: ArrayList([]const u8)) !usize {
            const terminal = Terminal(T){
                .allocator = self.allocator,
                .handler = handler,
                .parameter_names = parameter_names,
            };
            const index = self.terminals.items.len;

            try self.terminals.append(self.allocator, terminal);

            return index;
        }

        pub fn deinit(self: *Self) void {
            for (0..self.segments.items.len) |i| {
                switch (self.segments.items[i]) {
                    .static => self.segments.items[i].static.deinit(),
                    .parameter => self.segments.items[i].parameter.deinit(),
                    .wildcard => {},
                }
            }
            self.segments.deinit(self.allocator);

            for (0..self.terminals.items.len) |i| {
                self.terminals.items[i].deinit();
            }
            self.terminals.deinit(self.allocator);
        }
    };
}

test "Router creation and deinitialization" {
    const RouterType = Router(i32);
    var router = RouterType.init(std.testing.allocator);
    defer router.deinit();

    const terminalIndex = try router.addTerminal(42, .empty);

    const parameterIndex = try router.addParameter();
    router.segments.items[parameterIndex].parameter.terminal = terminalIndex;

    const staticIndex = try router.addStatic("users");
    try router.segments.items[staticIndex].static.addChild(parameterIndex);

    try std.testing.expectEqual(2, router.segments.items.len);
    try std.testing.expectEqual(1, router.terminals.items.len);
    try std.testing.expectEqual("users", router.segments.items[staticIndex].static.name);
    try std.testing.expectEqual(parameterIndex, router.segments.items[staticIndex].static.children.items[0]);
    try std.testing.expectEqual(terminalIndex, router.segments.items[parameterIndex].parameter.terminal);
    try std.testing.expectEqual(42, router.terminals.items[terminalIndex].handler);
}
