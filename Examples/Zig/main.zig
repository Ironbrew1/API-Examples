// Written for Zig 0.14. Run with: zig run main.zig
const std = @import("std");

const base_url = "https://ironbrew1.com";
const api_key = "IB1-APIKEYHERE";

const input_path = "input.lua";
const output_path = "output.lua";

const query = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false";

const retry_delay = 5;
const max_wait = 240;
const max_fails = 3;

const Queued = struct { uploadGuid: []const u8, statusUrl: []const u8 };
const Status = struct { status: []const u8, downloadUrl: ?[]const u8 = null };
const Response = struct { code: u32, body: []u8 };

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt ++ "\n", args);
    std.process.exit(1);
}

fn ok(code: u32) bool {
    return code >= 200 and code < 300;
}

fn request(allocator: std.mem.Allocator, client: *std.http.Client, method: std.http.Method, path: []const u8, payload: ?[]const u8) !Response {
    const url = try std.fmt.allocPrint(allocator, "{s}{s}", .{ base_url, path });
    defer allocator.free(url);

    var body = std.ArrayList(u8).init(allocator);
    const headers = [_]std.http.Header{
        .{ .name = "Key", .value = api_key },
        .{ .name = "Content-Type", .value = "text/plain" },
    };
    const result = try client.fetch(.{
        .location = .{ .url = url },
        .method = method,
        .extra_headers = &headers,
        .payload = payload,
        .response_storage = .{ .dynamic = &body },
        .max_append_size = 16 * 1024 * 1024,
    });
    return .{ .code = @intFromEnum(result.status), .body = try body.toOwnedSlice() };
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const stdout = std.io.getStdOut().writer();

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const source = std.fs.cwd().readFileAlloc(allocator, input_path, 64 * 1024 * 1024) catch |err|
        fail("Unable to read {s}: {}", .{ input_path, err });

    const queue_response = try request(allocator, &client, .POST, "/obfuscate?" ++ query, source);
    if (!ok(queue_response.code)) fail("Unable to queue obfuscation: {d}", .{queue_response.code});

    const queued = try std.json.parseFromSlice(Queued, allocator, queue_response.body, .{ .ignore_unknown_fields = true });
    try stdout.print("Obfuscation started with GUID: {s}\n", .{queued.value.uploadGuid});

    var elapsed: u64 = 0;
    var fails: u32 = 0;
    var wait: u64 = 0;

    while (true) {
        wait += retry_delay;
        std.time.sleep(wait * std.time.ns_per_s);
        elapsed += wait;

        const response = try request(allocator, &client, .GET, queued.value.statusUrl, null);
        if (!ok(response.code)) {
            fails += 1;
            try stdout.print("Status check failed with status: {d} ({d}/{d})\n", .{ response.code, fails, max_fails });
            if (fails >= max_fails or elapsed >= max_wait) fail("Obfuscation failed (fails: {d} | elapsed time: {d})", .{ fails, elapsed });
            continue;
        }

        const status = try std.json.parseFromSlice(Status, allocator, response.body, .{ .ignore_unknown_fields = true });

        if (std.mem.eql(u8, status.value.status, "completed")) {
            try stdout.print("Obfuscation completed in {d} seconds\n", .{elapsed});
            const download_url = status.value.downloadUrl orelse fail("Response is missing downloadUrl", .{});
            const download = try request(allocator, &client, .GET, download_url, null);
            if (!ok(download.code)) fail("Download failed with status: {d}", .{download.code});
            try std.fs.cwd().writeFile(.{ .sub_path = output_path, .data = download.body });
            try stdout.print("Saved obfuscated script to {s}\n", .{output_path});
            return;
        }

        if (std.mem.eql(u8, status.value.status, "failed") or elapsed >= max_wait) {
            fail("Obfuscation failed (status: {s} | elapsed time: {d})", .{ status.value.status, elapsed });
        }

        try stdout.print("Obfuscation is still in progress. Elapsed time: {d} seconds. Checking again in {d} seconds.\n", .{ elapsed, retry_delay + wait });
    }
}
