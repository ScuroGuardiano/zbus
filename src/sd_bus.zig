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
    last_errno: i32 = 0,
    // I can't use macro SD_BUS_ERROR_NULL because zig can't translate it :(((
    last_call_error: c_systemd.sd_bus_error = .{
        .name = null,
        .message = null,
        ._need_free = 0,
    },

    pub fn getLastErrno(self: ZBus) i32 {
        return self.last_errno;
    }

    /// Important note: error is only borrowed from ZBus. It will be destroyed
    /// when ZBus object is deinitted or next method is called. If you want to use it after ZBus is deinitted
    /// you must copy error by using `copyLastCallError`.
    pub fn getLastCallError(self: ZBus) SdBusError {
        const err = self.last_call_error;

        return SdBusError{
            .name = if (err.name != null) std.mem.sliceTo(err.name, 0) else null,
            .message = if (err.message != null) std.mem.sliceTo(err.message, 0) else null,
        };
    }

    pub fn copyLastCallError(self: ZBus, allocator: std.mem.Allocator) !SdBusErrorCopied {
        const err = self.last_call_error;
        const sourceName = if (err.name != null) std.mem.sliceTo(err.name, 0) else null;
        const sourceMessage = if (err.name != null) std.mem.sliceTo(err.message, 0) else null;
        var name: ?[:0]const u8 = null;
        var message: ?[:0]const u8 = null;

        if (sourceName != null) {
            name = try allocator.allocSentinel(u8, sourceName.len, 0);
            @memcpy(name, sourceName);
            errdefer allocator.free(name);
        }
        if (sourceMessage != null) {
            message = try allocator.allocSentinel(u8, sourceMessage.len, 0);
            @memcpy(message, sourceMessage);
            errdefer allocator.free(message);
        }

        return SdBusErrorCopied{ .name = name, .message = message, .allocator = allocator };
    }

    pub fn isLastMessageErrorSet(self: ZBus) bool {
        return c_systemd.sd_bus_error_is_set(&self.last_call_error) > 0;
    }

    pub fn deinit(self: *ZBus) void {
        c_systemd.sd_bus_error_free(&self.last_call_error);
        self.bus = c_systemd.sd_bus_unref(self.bus);
    }

    pub fn call(self: *ZBus, message: Message, usec: u64) ZBusError!Message {
        // It's safe to call it on SD_BUS_ERROR_NULL. It will also reset value to SD_BUS_ERROR_NULL.
        // We need to always call that before call to avoid memory leak.
        c_systemd.sd_bus_error_free(&self.last_call_error);
        var reply: ?*c_systemd.sd_bus_message = null;
        errdefer _ = c_systemd.sd_bus_message_unref(reply);

        const r = c_systemd.sd_bus_call(
            self.bus,
            message.m,
            usec,
            &self.last_call_error,
            &reply,
        );

        if (r < 0) {
            self.last_errno = r;
            return ZBusError.Errno;
        }

        return Message{ .m = reply };
    }

    pub fn messageNewMethodCall(
        self: *ZBus,
        destination: [:0]const u8,
        path: [:0]const u8,
        interface: [:0]const u8,
        member: [:0]const u8,
    ) ZBusError!Message {
        var message = Message{};
        const r = c_systemd.sd_bus_message_new_method_call(
            self.bus,
            &message.m,
            destination,
            path,
            interface,
            member,
        );
        if (r < 0) {
            self.last_errno = r;
            return ZBusError.Errno;
        }
        return message;
    }
};

pub const SdBusError = struct {
    name: ?[:0]const u8,
    message: ?[:0]const u8,
};

pub const SdBusErrorCopied = struct {
    name: ?[:0]const u8,
    message: ?[:0]const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *SdBusErrorCopied) void {
        if (self.name != null) {
            self.allocator.free(self.name);
        }
        if (self.message != null) {
            self.allocator.free(self.message);
        }
    }
};

pub const Message = struct {
    m: ?*c_systemd.sd_bus_message = null,
    last_errno: i32 = 0,

    pub fn getLastErrno(self: Message) i32 {
        return self.last_errno;
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
        const r = @call(.auto, c_systemd.sd_bus_message_append, .{ self.m, types } ++ args);
        if (r < 0) {
            self.last_errno = r;
            return ZBusError.Errno;
        }
    }

    /// Calls sd\_bus\_message\_open\_container from libsystemd.
    pub fn openContainer(self: *Message, containerType: u8, contents: [:0]const u8) ZBusError!void {
        const r = c_systemd.sd_bus_message_open_container(self.m, containerType, contents);
        if (r < 0) {
            self.last_errno = r;
            return ZBusError.Errno;
        }
    }

    /// Calls sd\_bus\_message\_close\_container from libsystemd.
    pub fn closeContainer(self: *Message) ZBusError!void {
        const r = c_systemd.sd_bus_message_close_container(self.m);
        if (r < 0) {
            self.last_errno = r;
            return ZBusError.Errno;
        }
    }

    /// Calls sd\_bus\_message\_read from libsystemd.
    /// Important note: strings are borrowed from message objects and **must be** copied if one wants to use them after message is freed.
    /// The same rule applies to UNIX file descriptors.
    /// For more information go [here](https://www.freedesktop.org/software/systemd/man/latest/sd_bus_message_read.html)
    pub fn read(self: *Message, types: [:0]const u8, args: anytype) ZBusError!bool {
        const r = @call(.auto, c_systemd.sd_bus_message_read, .{ self.m, types } ++ args);
        if (r < 0) {
            self.last_errno = r;
            return ZBusError.Errno;
        }
        return r > 0;
    }

    /// Calls sd\_bus\_message\_enter\_container from libsystemd.
    pub fn enterContainer(self: *Message, containerType: u8, contents: [:0]const u8) ZBusError!void {
        const r = c_systemd.sd_bus_message_enter_container(self.m, containerType, contents);
        if (r < 0) {
            self.last_errno = r;
            return ZBusError.Errno;
        }
    }

    /// Calls sd\_bus\_message\_exit\_container from libsystemd.
    pub fn exitContainer(self: *Message) ZBusError!void {
        const r = c_systemd.sd_bus_message_exit_container(self.m);
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
