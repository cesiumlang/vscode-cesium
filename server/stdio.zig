//! The process's standard streams, from zfls's src/stdio.zig.
//!
//! On Windows a parent can hand over a pipe opened for asynchronous
//! (overlapped) I/O, which the standard library's synchronous path does not
//! expect. These functions ask the handle how it was opened and set the
//! file's `nonblocking` flag to match.

const std = @import("std");
const sysinfo = @import("builtin");
const Io = std.Io;
const windows = std.os.windows;

const is_windows = sysinfo.os.tag == .windows;

pub fn stdin() Io.File {
    return adapt(Io.File.stdin());
}

pub fn stdout() Io.File {
    return adapt(Io.File.stdout());
}

/// `file` with the `nonblocking` flag that its handle needs
fn adapt(file: Io.File) Io.File {
    if (!is_windows) return file;
    var f = file;
    f.flags.nonblocking = isAsynchronous(file.handle);
    return f;
}

// FILE_MODE_INFORMATION's flags (wdm.h)
const FILE_SYNCHRONOUS_IO_ALERT: windows.ULONG = 0x10;
const FILE_SYNCHRONOUS_IO_NONALERT: windows.ULONG = 0x20;

/// Whether `handle` was opened for overlapped I/O; false when it cannot be
/// asked
fn isAsynchronous(handle: windows.HANDLE) bool {
    var iosb: windows.IO_STATUS_BLOCK = undefined;
    var mode: windows.ULONG = 0;
    const status = windows.ntdll.NtQueryInformationFile(handle, &iosb, &mode, @sizeOf(windows.ULONG), .Mode);
    if (status != .SUCCESS) return false;
    return mode & (FILE_SYNCHRONOUS_IO_ALERT | FILE_SYNCHRONOUS_IO_NONALERT) == 0;
}
