const std = @import("std");

const ws = @import("websocket");
const print = std.debug.print;
const mem = std.mem;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var app = try App.init(allocator);

    while (true) {
        var server = try ws.Server(Handler).init(allocator, .{
            .port = 9224,
            .address = "0.0.0.0",
            .handshake = .{
                .timeout = 25,
                .max_size = 4096,
                .max_headers = 16,
            },
        });

        app.server = &server;
        app.should_restart = false;
        // Arbitrary (application-specific) data to pass into each handler
        // Pass void ({}) into listen if you have none

        // this blocks
        try server.listen(&app);
        if (app.should_restart) {
            std.debug.print("Restarting server...\n", .{});
            continue; // Loop back to start a new server
        } else {
            break; // Exit if the server stopped for another reason
        }
    }
}

// This is your application-specific wrapper around a websocket connection
const Handler = struct {
    app: *App,
    conn: *ws.Conn,

    // You must define a public init function which takes
    pub fn init(h: ws.Handshake, conn: *ws.Conn, app: *App) !Handler {
        // add client to list of active clients
        try app.addClient(conn);

        _ = h; // we're not using this in our simple case

        return .{
            .app = app,
            .conn = conn,
        };
    }

    pub fn close(self: *Handler) void {
        std.debug.print("Connection closed\n", .{});
        self.app.removeClient(self.conn);
    }
    // You must defined a public clientMessage method
    pub fn clientMessage(self: *Handler, data: []const u8) !void {
        const allocator = self.app.allocator;
        var parsed = try std.json.parseFromSlice(Message, allocator, data, .{});
        defer parsed.deinit();

        const msg = parsed.value;
        print("Received type={s}, message={s}\n", .{ msg.clientType, msg.message });
        try self.app.updateClientType(msg.clientType, self.conn);

        try self.app.broadcast(msg);
    }
};
// init function.
const App = struct {
    allocator: mem.Allocator,
    server: ?*ws.Server(Handler), // Store the server instance
    should_restart: bool,
    clients: std.ArrayList(*ws.Conn),
    clientsType: Clients,
    pub fn init(allocator: mem.Allocator) !App {
        return App{
            .allocator = allocator,
            .clients = try std.ArrayList(*ws.Conn).initCapacity(allocator, 5),
            .clientsType = .{ .sender = null, .receiver = null },
            .server = null,
            .should_restart = false,
        };
    }
    pub fn removeClient(self: *App, conn: *ws.Conn) void {
        if (self.clientsType.sender == conn) {
            print("Sender disconected", .{});
            self.clientsType.sender = null;
        }
        if (self.clientsType.receiver == conn) {
            self.clientsType.receiver = null;
            print("Receiver disconected", .{});
        }
    }
    pub fn restartServer(self: *App) !void {
        // Signal the main loop to restart
        self.should_restart = true;
    }

    pub fn addClient(self: *App, conn: *ws.Conn) !void {
        try self.clients.append(conn);
        print("New client connected! Total: {d}\n", .{self.clients.items.len});
    }

    pub fn updateClientType(self: *App, clientType: []const u8, conn: *ws.Conn) !void {
        if (std.mem.eql(u8, clientType, "Sender")) {
            self.clientsType.sender = conn;
            print("Updated Sender connection\n", .{});
        } else if (std.mem.eql(u8, clientType, "Receiver")) {
            self.clientsType.receiver = conn;
            print("Updated Receiver connection\n", .{});
        }
    }

    pub fn broadcast(self: *App, msg: Message) !void {
        const typeOfClient: []const u8 = msg.clientType;
        const senderClient: []const u8 = "Sender";

        if (std.mem.eql(u8, typeOfClient, senderClient)) {
            print("Reached!!\n", .{});
            if (self.clientsType.receiver) |receiver| {
                var buf: [256]u8 = undefined;
                var stream = std.io.fixedBufferStream(&buf);
                const writer = stream.writer();

                // Serialize the message to JSON
                try std.json.stringify(msg, .{}, writer);

                // Get the written data as a slice
                const json_str = stream.buffer[0..stream.pos];

                print("Reached Pt 2 \n", .{});
                try receiver.write(json_str);
                //try self.clients.items[0].write(json_str);
                // _ = client.write(data) catch {};
            }
        } else if (self.clientsType.sender) |sender| {
            var buf: [256]u8 = undefined;
            var stream = std.io.fixedBufferStream(&buf);
            const writer = stream.writer();

            // Serialize the message to JSON
            try std.json.stringify(msg, .{}, writer);

            // Get the written data as a slice
            const json_str = stream.buffer[0..stream.pos];
            try sender.write(json_str);
            //try self.clients.items[1].write(json_str);
        } else {
            print("Unavailabel Client, Message: {s}", .{msg.message});
        }
    }
};
const Clients = struct { sender: ?*ws.Conn, receiver: ?*ws.Conn };
const Message = struct { clientType: []const u8, message: []const u8, status: []const u8 };
