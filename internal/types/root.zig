// The user will not be added until Phase 2 of this program's release.
// Right now, it will simply act as a stub.
pub const User = struct {
    id: i32,
    created_at: i64,
    updated_at: i64,
    deleted_at: ?i64,
};

// An account is tied to a user. It is used to manage multiple
// spending avenues (i.e., savings vs. debit, vs. credit, etc).
pub const Account = struct {
    pub const Errors = error{
        AccountRetrievalFailure,
        AccountSearchFailure,
        AccountCreationFailure,
        AccountDeletionFailure,
    };

    pub const DEF: []const u8 =
        \\ CREATE TABLE IF NOT EXISTS account (
        \\  id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        \\  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        \\  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        \\  deleted_at TIMESTAMP DEFAULT NULL,
        \\  initial_balance FLOAT,
        \\  name TEXT NOT NULL
        \\ );
    ;

    id: i32,
    created_at: i64,
    updated_at: i64,
    deleted_at: ?i64,
    initial_balance: ?f32,
    name: []const u8,

    // Get
    pub fn get_by_id(p: *pg.Pool, allocator: std.mem.Allocator, id: i32) Errors!?Account {
        const query =
            \\ SELECT id, created_at, updated_at, deleted_at, initial_balance, name FROM
            \\ acount WHERE id = $1 AND deleted_at IS NULL;
        ;

        const row = p.rowOpts(query, .{id}, .{ .column_names = true }) catch |err| {
            std.log.err("failed to get account with id {d} (err: {s})", .{ id, @errorName(err) });
            return Errors.AccountRetrievalFailure;
        };
        if (row) |r| {
            defer r.deinit();
            return r.to(Account, .{
                .dupe = true,
                .allocator = allocator,
            }) catch |err| {
                std.log.err("failed to map the row result to an account (err: {s})", .{@errorName(err)});
                return Errors.AccountRetrievalFailure;
            };
        }

        return null;
    }

    // Search
    pub fn search_by_name(p: *pg.Pool, allocator: std.mem.Allocator, name: []const u8, limit: u32, page: i32) Errors![]Account {
        const query =
            \\ SELECT id, created_at, updated_at, deleted_at, initial_balance, name FROM
            \\ account WHERE name ILIKE '%' || $1 ::text || '%' AND deleted_at IS NULL ORDER BY id ASC LIMIT $2 OFFSET $3
        ;

        const rows = p.queryOpts(query, .{ name, limit, page }, .{
            .column_names = true,
        }) catch |err| {
            std.log.err("failed to search the accounts by name (err: {s})", .{@errorName(err)});
            return Errors.AccountSearchFailure;
        };
        defer rows.deinit();

        var list: std.ArrayList(Account) = .empty;
        const mapper = rows.mapper(Account, .{ .allocator = allocator });

        while (mapper.next() catch |err| {
            std.log.err("failed to map the row search result to an account (err: {s})", .{@errorName(err)});
            return Errors.AccountSearchFailure;
        }) |acc| {
            list.append(allocator, acc) catch |err| {
                std.log.err("failed to append row search result to list (err: {s})", .{@errorName(err)});
                return Errors.AccountSearchFailure;
            };
        }

        return list.toOwnedSlice(allocator) catch |err| {
            std.log.err("failed to convert list to owned slice (err: {s})", .{@errorName(err)});
            return Errors.AccountSearchFailure;
        };
    }

    // Create
    pub fn create(p: *pg.Pool, allocator: std.mem.Allocator, name: []const u8, initial_balance: f32, comment: ?[]const u8) Errors!Account {
        const query =
            \\ INSERT INTO account (name, initial_balance) VALUES ($1, $2)
            \\ RETURNING id, created_at, updated_at, deleted_at, initial_balance, name;
        ;

        const row = p.row(query, .{ name, initial_balance, comment }) catch |err| {
            std.log.err("failed to create account with name '{s}', and initial balance of ${d} (err: {s})", .{ name, initial_balance, @errorName(err) });
            return Errors.AccountCreationFailure;
        };
        if (row) |r| {
            defer r.deinit();
            r.to(Account, .{
                .dupe = true,
                .allocator = allocator,
            }) catch |err| {
                std.log.err("failed to map the row result to an account (err: {s})", .{@errorName(err)});
                return Errors.AccountCreationFailure;
            };
        }
    }

    // Delete
    pub fn delete_by_id(p: *pg.Pool, id: i32) Errors!void {
        const query =
            \\ UPDATE account SET deleted_at = CURRENT_TIMESTAMP WHERE id = $1;
        ;

        _ = p.exec(query, .{id}) catch |err| {
            std.log.err("failed to delete account with id {d} (err: {s})", .{ id, @errorName(err) });
            return Errors.AccountDeletionFailure;
        };
    }
};

// Operations are performed on accounts, and they make the account
// lose money, or gain money.
pub const Operation = struct {
    pub const DEF: []const u8 =
        \\ CREATE TABLE IF NOT EXISTS operation (
        \\  id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        \\  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        \\  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        \\  deleted_at TIMESTAMP DEFAULT NULL,
        \\  value FLOAT NOT NULL,
        \\  date TIMESTAMP NOT NULL,
        \\  title TEXT NOT NULL,
        \\  comment TEXT,
        \\  account_id INT REFERENCES account(id) ON DELETE CASCADE
        \\ );
    ;

    id: i32,
    created_at: i64,
    updated_at: i64,
    deleted_at: ?i64,
    value: f32,
    date: i64,
    title: []const u8,
    comment: ?[]const u8,
    account_id: i32,

    // Get

    // Search

    // Create

    // Delete
};

const std = @import("std");
const pg = @import("pg");
