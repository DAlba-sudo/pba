const httpz = @import("httpz");
const pg = @import("pg");
const types = @import("../types/root.zig");
const analysis = @import("../analysis/root.zig");
const std = @import("std");
const json = std.json;
const time = @import("../time/root.zig");
const VERSION = @import("../root.zig").VERSION;

pub const api = @import("api/root.zig");

pub const App = struct {
    p: ?*pg.Pool,
};
pub const Server = httpz.Server(App);

pub fn health(_: App, _: *httpz.Request, res: *httpz.Response) !void {
    const info: struct {
        version: []const u8 = VERSION,
    } = .{};

    json.Stringify.value(info, .{}, res.writer()) catch |err| {
        std.log.err("failed to write general health info (err: {s})", .{@errorName(err)});
        return err;
    };

    res.setStatus(.ok);
}

const Payload = union(enum) {
    int: ?i32,
    float: ?f32,
    string: ?[]const u8,
};

pub fn Contract(map: *httpz.key_value.StringKeyValue, key: []const u8, result: Payload) !Payload {
    const v = map.get(key);

    var p: Payload = switch (result) {
        .string => Payload{ .string = result.string },
        .int => Payload{ .int = result.int },
        .float => Payload{ .float = result.float },
    };

    if (v) |value| {
        switch (result) {
            .string => {
                if (value.len == 0) {
                    p = Payload{ .string = null };
                } else {
                    p = Payload{ .string = value };
                }
            },
            .int => p = Payload{ .int = std.fmt.parseInt(i32, value, 10) catch blk: {
                break :blk null;
            } },
            .float => p = Payload{ .float = std.fmt.parseFloat(f32, value) catch blk: {
                break :blk null;
            } },
        }

        const has_value = switch (result) {
            .string => p.string != null,
            .int => p.int != null,
            .float => p.float != null,
        };

        if (has_value) {
            return p;
        }
    }

    const has_value = switch (result) {
        .string => p.string != null,
        .int => p.int != null,
        .float => p.float != null,
    };

    if (has_value) {
        return p;
    }

    return error.ContractViolation;
}
