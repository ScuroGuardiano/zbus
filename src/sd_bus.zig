const std = @import("std");
const c_systemd = @cImport({
    @cInclude("systemd/sd-bus.h");
});

pub const ZBusError = error{
    Errno,
};

threadlocal var last_errno: i32 = 0;
pub fn getLastErrno() i32 {
    return last_errno;
}

pub const ZBus = struct {
    bus: ?*c_systemd.sd_bus = null,

    pub fn deinit(self: *ZBus) void {
        self.bus = c_systemd.sd_bus_unref(self.bus);
    }
};

pub const Message = struct {
    m: ?*c_systemd.sd_bus_message = null,
    last_errno: i32 = 0,

    pub fn getLastErrno() i32 {
        return last_errno;
    }

    pub fn unref(self: *Message) void {
        c_systemd.sd_bus_message_unref(self.m);
        self.m = null;
    }

    /// Calls sd\_bus\_message\_append from libsystemd.
    /// Important note: string arguments **MUST BE** null terminated sentinel slices. Or bad stuff will happen.
    /// For more information go [here](https://www.freedesktop.org/software/systemd/man/latest/sd_bus_message_append.html)
    pub fn append(self: *Message, types: [:0]const u8, args: anytype) ZBusError!void {
        // I could force "types" to be compile time and validate args for correct types
        // but I am too lazy for that shit.
        const r = @call(.{}, c_systemd.sd_bus_message_append, .{ self.m, types } ++ args);
        if (r < 0) {
            self.last_errno = r;
            return ZBusError.Errno;
        }
    }

    /// Calls sd\_bus\_message\_read from libsystemd.
    /// Important note: strings are borrowed from message objects and **must be** copied if one wants to use them after message is freed.
    /// The same rule applies to UNIX file descriptors.
    /// For more information go [here](https://www.freedesktop.org/software/systemd/man/latest/sd_bus_message_read.html)
    pub fn read(self: *Message, types: [:0]const u8, args: anytype) ZBusError!void {
        const r = @call(.{}, c_systemd.sd_bus_message_read, .{ self.m, types } ++ args);
        if (r < 0) {
            self.last_errno = r;
            return ZBusError.Errno;
        }
    }
};

/// This function calls `sd\_bus\_default` from libsystemd, call `deinit` on returned object to destroy reference. From libsystemd docs:
/// `sd\_bus\_default()` acquires a bus connection object to the user bus when invoked from within a user slice (any session under "user-*.slice", e.g.: "user@1000.service"),
/// or to the system bus otherwise. The connection object is associated with the calling thread.
/// Each time the function is invoked from the same thread, the same object is returned, but its reference count is increased by one, as long as at least one reference is kept.
///
/// Read more [here](https://www.freedesktop.org/software/systemd/man/latest/sd_bus_default.html)
pub fn default() ZBusError!ZBus {
    var zbus = ZBus{};
    const ret = c_systemd.sd_bus_default(&zbus.bus);
    if (ret < 0) {
        last_errno = ret;
        return ZBusError.Errno;
    }
    return zbus;
}

/// This function calls `sd\_bus\_default\_user` from libsystemd, call deinit on returned object to destroy reference.
/// It works almost identically to `default` function but always connects to user bus.
/// From libsystemd docs:
/// `sd\_bus\_default\_user()` returns a user bus connection object associated with the calling thread.
///
/// Read more [here](https://www.freedesktop.org/software/systemd/man/latest/sd_bus_default.html)
pub fn defaultUser() ZBusError!ZBus {
    var zbus = ZBus{};
    const ret = c_systemd.sd_bus_default_user(&zbus.bus);
    if (ret < 0) {
        last_errno = ret;
        return ZBusError.Errno;
    }
    return zbus;
}

/// This function calls `sd\_bus\_default\_system` from libsystemd, call deinit on returned object to destroy reference.
/// It works almost identically to `default` function but always connects to the systemd bus.
/// From libsystemd docs:
/// `sd_bus_default_system()` is similar \[to the `sd_bus_default_user()`\], but connects to the system bus.
pub fn defaultSystem() ZBusError!ZBus {
    var zbus = ZBus{};
    const ret = c_systemd.sd_bus_default_system(&zbus.bus);
    if (ret < 0) {
        last_errno = ret;
        return ZBusError.Errno;
    }
    return zbus;
}
