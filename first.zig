const std = @import("std");
const net = std.net;
const stdout = std.io.getStdOut().writer();
const print = stdout.print();

pub fn main() !void {
    var buf: [300]u8 = undefined;
    var server = net.StreamServer.init(.{
        .reuse_port = true,
        .reuse_address = true,
    });
    defer {
        server.close();
        server.deinit();
    }

    const address = try net.Address.resolveIp("0.0.0.0", 300);
    try server.listen(address);

    try print("[INFO] Server listening on {}\n", .{server.listen_address});

    while (true) {
        const conn = try server.accept();

        const bytes = try conn.stream.read(&buf);

        try print("[INFO] Received {d} bytes from client - {s}\n", .{ bytes, buf[0..bytes] });
        _ = try conn.stream.writer("Hello from Server!");

        conn.stream.close();
    }
}
