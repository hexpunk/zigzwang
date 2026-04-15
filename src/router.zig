const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

pub const HttpVerb = enum {
    GET,
    HEAD,
    POST,
    PUT,
    DELETE,
    CONNECT,
    OPTIONS,
    TRACE,
    PATCH,
};

pub fn httpVerbFromString(verb: []const u8) !HttpVerb {
    return std.meta.stringToEnum(HttpVerb, verb) orelse error.InvalidHttpVerb;
}

test "httpVerbFromString" {
    try std.testing.expectEqual(.GET, try httpVerbFromString("GET"));
    try std.testing.expectEqual(.HEAD, try httpVerbFromString("HEAD"));
    try std.testing.expectEqual(.POST, try httpVerbFromString("POST"));
    try std.testing.expectEqual(.PUT, try httpVerbFromString("PUT"));
    try std.testing.expectEqual(.DELETE, try httpVerbFromString("DELETE"));
    try std.testing.expectEqual(.CONNECT, try httpVerbFromString("CONNECT"));
    try std.testing.expectEqual(.OPTIONS, try httpVerbFromString("OPTIONS"));
    try std.testing.expectEqual(.TRACE, try httpVerbFromString("TRACE"));
    try std.testing.expectEqual(.PATCH, try httpVerbFromString("PATCH"));
    try std.testing.expectEqual(error.InvalidHttpVerb, httpVerbFromString("INVALID"));
}

/// Terminals represent the end of a route and contain the HTTP verb, handler, and parameter names for that route.
fn Terminal(comptime T: type) type {
    return struct {
        verb: HttpVerb,
        handler: T,
        parameter_names: []const []const u8 = &.{},
    };
}

/// Static segments match a specific path segment and can have child segments and/or be terminal.
const Static = struct {
    name: []const u8,
    children: []const usize = &.{},
    terminals: []const usize = &.{},
};

/// Parameter segments match any single path segment and can have child segments and/or be terminal.
const Parameter = struct {
    children: []const usize = &.{},
    terminals: []const usize = &.{},
};

/// Wildcard segments match any remaining path segments and must be the last segment in a route.
const Wildcard = struct {
    terminals: []const usize = &.{},
};

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

const ParameterList = struct {
    allocator: Allocator,
    list: ArrayList([]const u8),

    pub fn init(allocator: Allocator) ParameterList {
        return ParameterList{
            .allocator = allocator,
            .list = .empty,
        };
    }

    pub fn append(self: *ParameterList, name: []const u8) !void {
        try self.list.append(self.allocator, name);
    }

    pub fn get(self: *ParameterList, index: usize) ?[]const u8 {
        return self.list.items[index];
    }

    pub fn deinit(self: *ParameterList) void {
        self.list.deinit(self.allocator);
    }
};

fn findSegment(comptime T: type, router: *const Router(T), path: []const u8, parameters: *ParameterList, current_index: usize) !?usize {
    switch (router.segments[current_index]) {
        .static => |static| {
            // Special handling for root segment: it should match paths both with and without leading slash
            if (current_index == 0) {
                // This is the root segment (empty name)
                // Skip leading "/" if present, otherwise treat the entire path as the rest
                const rest = if (path.len > 0 and path[0] == '/') path[1..] else path;
                if (rest.len == 0) {
                    return current_index;
                } else {
                    for (static.children) |child_index| {
                        const result = try findSegment(T, router, rest, parameters, child_index);
                        if (result) |index| {
                            return index;
                        }
                    }
                }
            } else {
                // Regular static segment matching
                const next_slash = std.mem.indexOf(u8, path, "/") orelse path.len;
                const segment_name = path[0..next_slash];

                if (std.mem.eql(u8, static.name, segment_name)) {
                    const rest = path[@min(next_slash + 1, path.len)..];
                    if (rest.len == 0) {
                        return current_index;
                    } else {
                        for (static.children) |child_index| {
                            const result = try findSegment(T, router, rest, parameters, child_index);
                            if (result) |index| {
                                return index;
                            }
                        }
                    }
                }
            }

            return null;
        },
        .parameter => |param| {
            const next_slash = std.mem.indexOf(u8, path, "/") orelse path.len;
            const param_value = path[0..next_slash];
            try parameters.append(param_value);

            const rest = path[@min(next_slash + 1, path.len)..];
            if (rest.len == 0) {
                return current_index;
            } else {
                for (param.children) |child_index| {
                    const result = try findSegment(T, router, rest, parameters, child_index);
                    if (result) |index| {
                        return index;
                    }
                }
            }
        },
        .wildcard => {
            try parameters.append(path);
            return current_index;
        },
    }

    return null;
}

fn Router(comptime T: type) type {
    return struct {
        const Self = @This();

        segments: []const Segment = &.{},
        terminals: []const Terminal(T) = &.{},

        pub fn match(self: Self, allocator: Allocator, verb: HttpVerb, path: []const u8, parameters: *StringHashMap([]const u8)) !?T {
            var param_list = ParameterList.init(allocator);
            defer param_list.deinit();

            const segment_index = try findSegment(T, &self, path, &param_list, 0);
            if (segment_index) |i| {
                const terminal_indexes = switch (self.segments[i]) {
                    .static => self.segments[i].static.terminals,
                    .parameter => self.segments[i].parameter.terminals,
                    .wildcard => self.segments[i].wildcard.terminals,
                };

                for (terminal_indexes) |j| {
                    const terminal = self.terminals[j];

                    if (terminal.verb == verb) {
                        for (terminal.parameter_names, 0..) |param_name, k| {
                            try parameters.put(param_name, param_list.get(k) orelse unreachable);
                        }

                        return terminal.handler;
                    }
                }
            }

            return null;
        }
    };
}

test "Router.match" {
    const router = comptime createRouter(i32, &.{
        .{ .GET, "/", 123 },
        .{ .GET, "/users/:id/profile/*path", 42 },
        .{ .GET, "/static/", 99 },
        .{ .GET, "/:lone", 7 },
    });

    const allocator = std.testing.allocator;
    var params = StringHashMap([]const u8).init(allocator);
    defer params.deinit();

    const result = try router.match(allocator, .GET, "users/123/profile/settings/privacy", &params);
    try std.testing.expectEqual(42, result.?);
    try std.testing.expectEqualStrings("123", params.get("id") orelse @panic("Expected parameter 'id' not found"));
    try std.testing.expectEqualStrings("settings/privacy", params.get("path") orelse @panic("Expected parameter 'path' not found"));

    var root_result = try router.match(allocator, .GET, "", &params);
    try std.testing.expectEqual(123, root_result.?);
    root_result = try router.match(allocator, .GET, "/", &params);
    try std.testing.expectEqual(123, root_result.?);

    var static_result = try router.match(allocator, .GET, "static/", &params);
    try std.testing.expectEqual(99, static_result.?);
    static_result = try router.match(allocator, .GET, "/static", &params);
    try std.testing.expectEqual(99, static_result.?);
    static_result = try router.match(allocator, .GET, "static", &params);
    try std.testing.expectEqual(99, static_result.?);

    var lone_result = try router.match(allocator, .GET, "anything/", &params);
    try std.testing.expectEqual(7, lone_result.?);
    try std.testing.expectEqualStrings("anything", params.get("lone") orelse @panic("Expected parameter 'lone' not found"));
    lone_result = try router.match(allocator, .GET, "something", &params);
    try std.testing.expectEqual(7, lone_result.?);
    try std.testing.expectEqualStrings("something", params.get("lone") orelse @panic("Expected parameter 'lone' not found"));
}

fn addTerminal(comptime T: type, router: *Router(T), verb: HttpVerb, handler: T, parameter_names: []const []const u8) usize {
    comptime {
        const terminal_index = router.terminals.len;
        const new_terminal: Terminal(T) = .{ .verb = verb, .handler = handler, .parameter_names = parameter_names };
        const new_term_arr = [_]Terminal(T){new_terminal};
        router.terminals = router.terminals ++ &new_term_arr;
        return terminal_index;
    }
}

test "addTerminal" {
    const index, const router = comptime blk: {
        var r = Router(i32){
            .segments = &.{},
            .terminals = &.{},
        };

        const handler = 42;
        const parameter_names = &.{"id"};
        const terminal_index = addTerminal(i32, &r, .GET, handler, parameter_names);

        break :blk .{ terminal_index, r };
    };

    try std.testing.expectEqual(0, index);
    try std.testing.expectEqual(42, router.terminals[index].handler);
    try std.testing.expectEqual(1, router.terminals[index].parameter_names.len);
    try std.testing.expectEqualStrings("id", router.terminals[index].parameter_names[0]);
}

fn appendSegment(comptime T: type, router: *Router(T), new_segment: Segment) usize {
    comptime {
        const segment_index = router.segments.len;
        const new_seg_arr = [_]Segment{new_segment};
        router.segments = router.segments ++ &new_seg_arr;
        return segment_index;
    }
}

/// Adds a new segment to the router based on the segment name.
fn addSegment(comptime T: type, router: *Router(T), segment_name: []const u8) usize {
    comptime {
        const new_segment: Segment = switch (getSegmentType(segment_name)) {
            .static => .{ .static = .{ .name = segment_name } },
            .parameter => .{ .parameter = .{} },
            .wildcard => .{ .wildcard = .{} },
        };

        return appendSegment(T, router, new_segment);
    }
}

test "addSegment: static segment" {
    const index, const router = comptime blk: {
        var r = Router(i32){
            .segments = &.{},
            .terminals = &.{},
        };

        const segment_index = addSegment(i32, &r, "users");

        break :blk .{ segment_index, r };
    };

    try std.testing.expectEqual(0, index);
    try std.testing.expectEqualStrings("users", router.segments[index].static.name);
}

test "addSegment: parameter segment" {
    const index, const router = comptime blk: {
        var r = Router(i32){
            .segments = &.{},
            .terminals = &.{},
        };

        const segment_index = addSegment(i32, &r, ":id");

        break :blk .{ segment_index, r };
    };

    try std.testing.expectEqual(0, index);
    try std.testing.expectEqual(Parameter, @TypeOf(router.segments[index].parameter));
}

test "addSegment: wildcard segment" {
    const index, const router = comptime blk: {
        var r = Router(i32){
            .segments = &.{},
            .terminals = &.{},
        };

        const segment_index = addSegment(i32, &r, "*the/rest/of/the/path");

        break :blk .{ segment_index, r };
    };

    try std.testing.expectEqual(0, index);
    try std.testing.expectEqual(Wildcard, @TypeOf(router.segments[index].wildcard));
}

fn replaceSegment(comptime T: type, router: *Router(T), segment_index: usize, new_segment: Segment) void {
    comptime {
        const before = router.segments[0..segment_index];
        const after = router.segments[segment_index + 1 ..];
        const new_seg_arr = [_]Segment{new_segment};
        router.segments = before ++ &new_seg_arr ++ after;
    }
}

fn insertAt(comptime T: type, slice: []const T, index: usize, value: T) []const T {
    comptime {
        const before = slice[0..index];
        const after = slice[index..];
        const new_arr = [_]T{value};
        return before ++ &new_arr ++ after;
    }
}

test "insertAt" {
    const result1 = comptime insertAt(i32, &.{ 1, 2, 4 }, 2, 3);
    try std.testing.expectEqual(4, result1.len);
    try std.testing.expectEqual(1, result1[0]);
    try std.testing.expectEqual(2, result1[1]);
    try std.testing.expectEqual(3, result1[2]);
    try std.testing.expectEqual(4, result1[3]);

    const result2 = comptime insertAt(i32, &.{ 1, 2, 3 }, 0, 0);
    try std.testing.expectEqual(4, result2.len);
    try std.testing.expectEqual(0, result2[0]);
    try std.testing.expectEqual(1, result2[1]);
    try std.testing.expectEqual(2, result2[2]);
    try std.testing.expectEqual(3, result2[3]);

    const result3 = comptime insertAt(i32, &.{ 1, 2, 3 }, 3, 4);
    try std.testing.expectEqual(4, result3.len);
    try std.testing.expectEqual(1, result3[0]);
    try std.testing.expectEqual(2, result3[1]);
    try std.testing.expectEqual(3, result3[2]);
    try std.testing.expectEqual(4, result3[3]);

    const result4 = comptime insertAt(i32, &.{}, 0, 1);
    try std.testing.expectEqual(1, result4.len);
    try std.testing.expectEqual(1, result4[0]);
}

fn insertSorted(comptime T: type, router: *Router(T), children: []const usize, new_child: usize) []const usize {
    comptime {
        const new_child_segment = router.segments[new_child];

        var i: usize = 0;
        while (i < children.len) : (i += 1) {
            switch (router.segments[children[i]]) {
                .static => |this_child| {
                    switch (new_child_segment) {
                        .static => |new_child_static| switch (std.mem.order(u8, this_child.name, new_child_static.name)) {
                            .lt => continue,
                            .eq => @panic("Duplicate static segment names are not allowed"),
                            .gt => break,
                        },
                        .parameter, .wildcard => continue, // Static segments come before parameter and wildcard segments
                    }
                },
                .parameter => switch (new_child_segment) {
                    .static => break, // Static segments come before parameter segments
                    .parameter => @panic("Duplicate parameter segments are not allowed"),
                    .wildcard => continue,
                },
                .wildcard => switch (new_child_segment) {
                    .static, .parameter => break, // Static and parameter segments come before wildcard segments
                    .wildcard => @panic("Duplicate wildcard segments are not allowed"),
                },
            }
        }

        return insertAt(usize, children, i, new_child);
    }
}

test "insertSorted" {
    const new_children = comptime blk: {
        var r = Router(i32){
            .segments = &.{},
            .terminals = &.{},
        };

        _ = addSegment(i32, &r, "a");
        _ = addSegment(i32, &r, "b");
        _ = addSegment(i32, &r, ":id");
        _ = addSegment(i32, &r, "*path");

        var children: []const usize = &.{};
        children = insertSorted(i32, &r, children, 3);
        children = insertSorted(i32, &r, children, 2);
        children = insertSorted(i32, &r, children, 1);
        children = insertSorted(i32, &r, children, 0);

        break :blk children;
    };

    try std.testing.expectEqual(4, new_children.len);
    try std.testing.expectEqual(0, new_children[0]);
    try std.testing.expectEqual(1, new_children[1]);
    try std.testing.expectEqual(2, new_children[2]);
    try std.testing.expectEqual(3, new_children[3]);
}

fn addChild(comptime T: type, router: *Router(T), segment_index: usize, new_child: usize) void {
    comptime {
        const old_segment = router.segments[segment_index];
        var new_segment: Segment = undefined;

        switch (old_segment) {
            .static => new_segment = .{
                .static = .{
                    .name = old_segment.static.name,
                    .children = insertSorted(T, router, old_segment.static.children, new_child),
                    .terminals = old_segment.static.terminals,
                },
            },
            .parameter => new_segment = .{
                .parameter = .{
                    .children = insertSorted(T, router, old_segment.parameter.children, new_child),
                    .terminals = old_segment.parameter.terminals,
                },
            },
            .wildcard => @panic("Wildcard segments cannot have children"),
        }

        replaceSegment(T, router, segment_index, new_segment);
    }
}

fn prependTerminal(comptime T: type, router: *Router(T), segment_index: usize, terminal_index: usize) void {
    comptime {
        const old_segment = router.segments[segment_index];
        var new_segment: Segment = undefined;

        switch (old_segment) {
            .static => new_segment = .{
                .static = .{
                    .name = old_segment.static.name,
                    .children = old_segment.static.children,
                    .terminals = .{terminal_index} ++ old_segment.static.terminals,
                },
            },
            .parameter => new_segment = .{
                .parameter = .{
                    .children = old_segment.parameter.children,
                    .terminals = .{terminal_index} ++ old_segment.parameter.terminals,
                },
            },
            .wildcard => new_segment = .{
                .wildcard = .{
                    .terminals = .{terminal_index} ++ old_segment.wildcard.terminals,
                },
            },
        }

        replaceSegment(T, router, segment_index, new_segment);
    }
}

test "prependTerminal: static segment" {
    const router, const segment_index, const term_index1, const term_index2 = comptime blk: {
        var r = Router(i32){
            .segments = &.{},
            .terminals = &.{},
        };

        const term_index1 = addTerminal(i32, &r, .GET, 42, &.{});
        const term_index2 = addTerminal(i32, &r, .POST, 99, &.{});
        const segment_index = addSegment(i32, &r, "users");
        prependTerminal(i32, &r, segment_index, term_index1);
        prependTerminal(i32, &r, segment_index, term_index2);

        break :blk .{ r, segment_index, term_index1, term_index2 };
    };

    try std.testing.expectEqual(0, segment_index);
    try std.testing.expectEqual(0, term_index1);
    try std.testing.expectEqual(1, term_index2);
    try std.testing.expectEqual(term_index2, router.segments[segment_index].static.terminals[0]);
    try std.testing.expectEqual(term_index1, router.segments[segment_index].static.terminals[1]);
}

test "prependTerminal: parameter segment" {
    const router, const segment_index, const term_index1, const term_index2 = comptime blk: {
        var r = Router(i32){
            .segments = &.{},
            .terminals = &.{},
        };

        const term_index1 = addTerminal(i32, &r, .GET, 42, &.{"id"});
        const term_index2 = addTerminal(i32, &r, .POST, 99, &.{"id"});
        const segment_index = addSegment(i32, &r, ":id");
        prependTerminal(i32, &r, segment_index, term_index1);
        prependTerminal(i32, &r, segment_index, term_index2);

        break :blk .{ r, segment_index, term_index1, term_index2 };
    };

    try std.testing.expectEqual(0, segment_index);
    try std.testing.expectEqual(0, term_index1);
    try std.testing.expectEqual(1, term_index2);
    try std.testing.expectEqual(term_index2, router.segments[segment_index].parameter.terminals[0]);
    try std.testing.expectEqual(term_index1, router.segments[segment_index].parameter.terminals[1]);
}

test "prependTerminal: wildcard segment" {
    const router, const segment_index, const term_index1, const term_index2 = comptime blk: {
        var r = Router(i32){
            .segments = &.{},
            .terminals = &.{},
        };

        const term_index1 = addTerminal(i32, &r, .GET, 42, &.{});
        const term_index2 = addTerminal(i32, &r, .POST, 99, &.{});
        const segment_index = addSegment(i32, &r, "*the/rest/of/the/path");
        prependTerminal(i32, &r, segment_index, term_index1);
        prependTerminal(i32, &r, segment_index, term_index2);

        break :blk .{ r, segment_index, term_index1, term_index2 };
    };

    try std.testing.expectEqual(0, segment_index);
    try std.testing.expectEqual(0, term_index1);
    try std.testing.expectEqual(1, term_index2);
    try std.testing.expectEqual(term_index2, router.segments[segment_index].wildcard.terminals[0]);
    try std.testing.expectEqual(term_index1, router.segments[segment_index].wildcard.terminals[1]);
}

/// Splits a path into segments based on '/' and handles wildcard segments ('*').
fn splitPath(path: []const u8) []const []const u8 {
    comptime {
        var segments: []const []const u8 = &.{};
        var start: usize = 0;

        for (0..path.len) |i| {
            if (path[i] == '/') {
                if (i > start) {
                    segments = segments ++ &[_][]const u8{path[start..i]};
                }
                start = i + 1;
            } else if (path[i] == '*') {
                break;
            }
        }

        if (start < path.len) {
            segments = segments ++ &[_][]const u8{path[start..]};
        }

        return segments;
    }
}

test "splitPath" {
    const path = "/users/:id/profile/*the/rest/of/the/path";
    const segments = comptime splitPath(path);

    try std.testing.expectEqual(4, segments.len);
    try std.testing.expectEqualStrings("users", segments[0]);
    try std.testing.expectEqualStrings(":id", segments[1]);
    try std.testing.expectEqualStrings("profile", segments[2]);
    try std.testing.expectEqualStrings("*the/rest/of/the/path", segments[3]);
}

fn getParameterNames(segments: []const []const u8) []const []const u8 {
    comptime {
        var parameter_names: []const []const u8 = &.{};
        for (segments) |segment| {
            if (segment.len > 0 and (segment[0] == ':' or segment[0] == '*')) {
                parameter_names = parameter_names ++ &[_][]const u8{segment[1..]};
            }
        }
        return parameter_names;
    }
}

test "getParameterNames" {
    const segments = &.{ "users", ":id", "profile", "*the/rest/of/the/path" };
    const parameter_names = comptime getParameterNames(segments);

    try std.testing.expectEqual(2, parameter_names.len);
    try std.testing.expectEqualStrings("id", parameter_names[0]);
    try std.testing.expectEqualStrings("the/rest/of/the/path", parameter_names[1]);
}

fn getSegmentType(segment: []const u8) SegmentType {
    if (segment.len > 0) {
        if (segment[0] == ':') {
            return .parameter;
        } else if (segment[0] == '*') {
            return .wildcard;
        }
    }
    return .static;
}

test "getSegmentType" {
    try std.testing.expectEqual(.static, getSegmentType("users"));
    try std.testing.expectEqual(.parameter, getSegmentType(":id"));
    try std.testing.expectEqual(.wildcard, getSegmentType("*path"));
}

/// Matches a segment name against a slice of child segment indices.
/// Returns the segment index of the match, or null if no match is found.
fn matchSegment(comptime T: type, router: *Router(T), children: []const usize, segment_name: []const u8) ?usize {
    comptime {
        switch (getSegmentType(segment_name)) {
            .static => {
                var i: usize = 0;
                while (i < children.len) : (i += 1) {
                    switch (router.segments[children[i]]) {
                        .static => |child| if (std.mem.eql(u8, child.name, segment_name)) {
                            return children[i];
                        } else {
                            continue;
                        },
                        .parameter, .wildcard => continue,
                    }
                }

                return null;
            },
            .parameter => {
                var i: usize = 0;
                while (i < children.len) : (i += 1) {
                    switch (router.segments[children[i]]) {
                        .parameter => return children[i],
                        .static, .wildcard => continue,
                    }
                }

                return null;
            },
            .wildcard => {
                var i: usize = 0;
                while (i < children.len) : (i += 1) {
                    switch (router.segments[children[i]]) {
                        .wildcard => return children[i],
                        .static, .parameter => continue,
                    }
                }

                return null;
            },
        }
    }
}

/// Gets the child segment index for a given parent segment index and segment name.
/// Returns the child segment index if a match is found, or null if no match is found.
fn getChild(comptime T: type, router: *Router(T), parent_index: usize, segment_name: []const u8) ?usize {
    comptime {
        switch (router.segments[parent_index]) {
            .static => |parent| return matchSegment(T, router, parent.children, segment_name),
            .parameter => |parent| return matchSegment(T, router, parent.children, segment_name),
            .wildcard => {
                @panic("Wildcard segments cannot have children");
            },
        }
    }
}

test "getChild: static segment" {
    const child_index1, const child_index2 = comptime blk: {
        var r = Router(i32){
            .segments = &.{},
            .terminals = &.{},
        };

        const parent_index = addSegment(i32, &r, "users");
        const child_index = addSegment(i32, &r, "profile");
        addChild(i32, &r, parent_index, child_index);

        const retrieved_child_index = getChild(i32, &r, parent_index, "profile");
        const non_existent_child_index = getChild(i32, &r, parent_index, "settings");

        break :blk .{ retrieved_child_index, non_existent_child_index };
    };

    try std.testing.expectEqual(1, child_index1);
    try std.testing.expectEqual(null, child_index2);
}

test "getChild: parameter segment" {
    const child_index = comptime blk: {
        var r = Router(i32){
            .segments = &.{},
            .terminals = &.{},
        };

        const parent_index = addSegment(i32, &r, ":id1");
        const child_index = addSegment(i32, &r, ":id2");
        addChild(i32, &r, parent_index, child_index);

        const retrieved_child_index = getChild(i32, &r, parent_index, ":id");

        break :blk retrieved_child_index;
    };

    try std.testing.expectEqual(1, child_index);
}

test "getChild: wildcard segment" {
    const child_index = comptime blk: {
        var r = Router(i32){
            .segments = &.{},
            .terminals = &.{},
        };

        const parent_index = addSegment(i32, &r, ":id");
        const child_index = addSegment(i32, &r, "*the/rest/of/the/path");
        addChild(i32, &r, parent_index, child_index); // Wildcard segments must be terminal

        const retrieved_child_index = getChild(i32, &r, parent_index, "*path");

        break :blk retrieved_child_index;
    };

    try std.testing.expectEqual(1, child_index);
}

fn addRoute(comptime T: type, router: *Router(T), segments: []const []const u8, terminal_index: usize, parent_index: usize) void {
    comptime {
        // If segments is empty, set the terminal for the parent segment and return
        if (segments.len == 0) {
            prependTerminal(T, router, parent_index, terminal_index);

            return;
        }

        const child_index = getChild(T, router, parent_index, segments[0]);
        // If a child segment matching the first segment already exists, recursively add the route to that child
        if (child_index) |i| {
            addRoute(T, router, segments[1..], terminal_index, i);

            return;
        }

        const new_segment_index = addSegment(T, router, segments[0]);
        addChild(T, router, parent_index, new_segment_index);
        addRoute(T, router, segments[1..], terminal_index, new_segment_index);
    }
}

pub fn createRouter(comptime T: type, routes: []const struct { HttpVerb, []const u8, T }) Router(T) {
    comptime {
        var router = Router(T){
            .segments = &.{
                // Root segment
                .{
                    .static = .{
                        .name = "<root>",
                    },
                },
            },
            .terminals = &.{},
        };

        for (routes) |route| {
            const verb = route[0];
            const path = route[1];
            const value = route[2];

            const segments = splitPath(path);
            const parameter_names = getParameterNames(segments);
            const terminal_index = addTerminal(T, &router, verb, value, parameter_names);

            addRoute(T, &router, segments, terminal_index, 0);
        }

        return router;
    }
}

test "createRouter" {
    const router = comptime createRouter(i32, &.{
        .{ .GET, "/a", 1 },
        .{ .GET, "/b", 2 },
        .{ .GET, "/:id", 3 },
        .{ .GET, "/*path", 4 },
    });

    try std.testing.expectEqual(5, router.segments.len);
    try std.testing.expectEqualStrings("a", router.segments[1].static.name);
    try std.testing.expectEqualStrings("b", router.segments[2].static.name);
    try std.testing.expectEqual(Parameter, @TypeOf(router.segments[3].parameter));
    try std.testing.expectEqual(Wildcard, @TypeOf(router.segments[4].wildcard));
}
