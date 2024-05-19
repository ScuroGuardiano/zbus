const std = @import("std");
const zbus = @import("./sd_bus.zig");

pub fn main() !void {
    var bus = try zbus.defaultSystem();
    defer bus.deinit();
    const callMessage = try bus.messageNewMethodCall(
        "org.freedesktop.systemd1",
        "/org/freedesktop/systemd1",
        "org.freedesktop.systemd1.Manager",
        "ListUnits",
    );
    var reply = try bus.call(callMessage, 0);
    const RetType = struct {
        [*c]const u8 = undefined,
        [*c]const u8 = undefined,
        [*c]const u8 = undefined,
        [*c]const u8 = undefined,
        [*c]const u8 = undefined,
        [*c]const u8 = undefined,
        [*c]const u8 = undefined,
        u32 = 0,
        [*c]const u8 = undefined,
        [*c]const u8 = undefined,
    };

    try reply.enterContainer('a', "(ssssssouso)");

    const allocator = std.heap.c_allocator;

    while (true) {
        var x = try allocator.create(RetType);

        const r = try reply.read("(ssssssouso)", .{ &x[0], &x[1], &x[2], &x[3], &x[4], &x[5], &x[6], &x[7], &x[8], &x[9] });
        if (!r) break;
        std.debug.print("{s}:{s}:{s}:{s}:{s}:{s}:{s}:{d}:{s}:{s}\n", x.*);
    }

    try reply.exitContainer();
}
