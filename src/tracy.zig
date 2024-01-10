const std = @import("std");
const SourceLocation = std.builtin.SourceLocation;

const options = @import("options");

const enabled = options.enable;
const has_callstack = options.has_callstack;
const callstack_depth = options.callstack_depth;

const message_buffer_size = if (enabled) 4096 else 0;

pub const PlotFormat = enum(c_uint) {
    number = 0,
    memory = 1,
    percentage = 2,
    watt = 3,
};

pub const SourceLocationData = extern struct {
    name: ?[*:0]const u8,
    function: [*:0]const u8,
    file: [*:0]const u8,
    line: u32,
    color: u32,
};

pub const ZoneContext = extern struct {
    id: u32,
    active: c_int,

    pub fn end(self: ZoneContext) void {
        ___tracy_emit_zone_end(self);
    }

    pub fn text(self: ZoneContext, txt: [:0]const u8) void {
        ___tracy_emit_zone_text(self, txt.ptr, txt.len);
    }

    pub fn name(self: ZoneContext, txt: [:0]const u8) void {
        ___tracy_emit_zone_name(self, txt.ptr, txt.len);
    }

    pub fn color(self: ZoneContext, c: u32) void {
        ___tracy_emit_zone_color(self, c);
    }

    pub fn value(self: ZoneContext, v: u64) void {
        ___tracy_emit_zone_value(self, v);
    }

    extern fn ___tracy_emit_zone_end(ctx: ZoneContext) void;
    extern fn ___tracy_emit_zone_text(ctx: ZoneContext, txt: [*]const u8, size: usize) void;
    extern fn ___tracy_emit_zone_name(ctx: ZoneContext, txt: [*]const u8, size: usize) void;
    extern fn ___tracy_emit_zone_color(ctx: ZoneContext, color: u32) void;
    extern fn ___tracy_emit_zone_value(ctx: ZoneContext, value: u64) void;
};

pub const GpuTimeData = extern struct {
    gpuTime: i64,
    queryId: u16,
    context: u8,
};

pub const GpuZoneBeginData = extern struct {
    srcloc: u64,
    queryId: u16,
    context: u8,
};

pub const GpuZoneBeginCallstackData = extern struct {
    srcloc: u64,
    depth: c_int,
    queryId: u16,
    context: u8,
};

pub const GpuZoneEndData = extern struct {
    queryId: u16,
    context: u8,
};

pub const GpuNewContextData = extern struct {
    gpuTime: i64,
    period: f32,
    context: u8,
    flags: u8,
    type: u8,
};

pub const GpuContextNameData = extern struct {
    context: u8,
    name: [*c]const u8,
    len: u16,
};

pub const GpuCalibrationData = extern struct {
    gpuTime: i64,
    cpuDelta: i64,
    context: u8,
};

fn staticifySrcLoc(
    comptime src_loc: SourceLocation,
    name: ?[*:0]const u8,
    color: u32,
) *SourceLocationData {
    const static = struct {
        var src: SourceLocationData = undefined;
    };

    static.src = .{
        .name = name,
        .function = src_loc.fn_name,
        .file = src_loc.file,
        .line = src_loc.line,
        .color = color,
    };

    return &static.src;
}

fn zoneBegin(
    comptime src_loc: SourceLocation,
    name: ?[*:0]const u8,
    color: u32,
) ZoneContext {
    if (enabled) {
        if (has_callstack) {
            return ___tracy_emit_zone_begin_callstack(
                staticifySrcLoc(src_loc, name, color),
                callstack_depth,
                1,
            );
        } else {
            return ___tracy_emit_zone_begin(
                staticifySrcLoc(src_loc, name, color),
                1,
            );
        }
    }
}

pub fn zone(comptime src_loc: SourceLocation) ZoneContext {
    return zoneBegin(src_loc, null, 0);
}

pub fn zoneN(comptime src_loc: SourceLocation, name: [*:0]const u8) ZoneContext {
    return zoneBegin(src_loc, name, 0);
}

pub fn zoneC(comptime src_loc: SourceLocation, color: u32) ZoneContext {
    return zoneBegin(src_loc, null, color);
}

pub fn zoneNC(comptime src_loc: SourceLocation, name: [*:0]const u8, color: u32) ZoneContext {
    return zoneBegin(src_loc, name, color);
}

pub fn frameMark() void {
    if (enabled) {
        ___tracy_emit_frame_mark(null);
    }
}

pub fn frameMarkNamed(name: [*:0]const u8) void {
    if (enabled) {
        ___tracy_emit_frame_mark(name);
    }
}

pub fn frameMarkStart(name: [*:0]const u8) void {
    if (enabled) {
        ___tracy_emit_frame_mark_start(name);
    }
}

pub fn frameMarkEnd(name: [*:0]const u8) void {
    if (enabled) {
        ___tracy_emit_frame_mark_end(name);
    }
}

pub const TracingAllocator = struct {
    parent: std.mem.Allocator,

    pub fn init(parent: std.mem.Allocator) TracingAllocator {
        return .{ .parent = parent };
    }

    pub fn allocator(self: *TracingAllocator) std.mem.Allocator {
        return .{
            .ptr = @ptrCast(self),
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *TracingAllocator = @ptrCast(@alignCast(ctx));
        const ptr = self.parent.rawAlloc(len, ptr_align, ret_addr);

        if (enabled and ptr != null) {
            if (has_callstack) {
                ___tracy_emit_memory_alloc_callstack(@ptrCast(ptr), len, callstack_depth, 1);
            } else {
                ___tracy_emit_memory_alloc(@ptrCast(ptr), len, 1);
            }
        }

        return ptr;
    }

    fn resize(ctx: *anyopaque, buf: []u8, ptr_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *TracingAllocator = @ptrCast(@alignCast(ctx));
        const old_ptr: *anyopaque = @ptrCast(buf.ptr);
        const res = self.parent.rawResize(buf, ptr_align, new_len, ret_addr);

        if (enabled and res) {
            if (has_callstack) {
                ___tracy_emit_memory_free_callstack(old_ptr, callstack_depth, 1);
                ___tracy_emit_memory_alloc_callstack(@ptrCast(buf.ptr), new_len, callstack_depth, 1);
            } else {
                ___tracy_emit_memory_free(old_ptr, 1);
                ___tracy_emit_memory_alloc(@ptrCast(buf.ptr), new_len, 1);
            }
        }

        return res;
    }

    fn free(ctx: *anyopaque, buf: []u8, ptr_align: u8, ret_addr: usize) void {
        const self: *TracingAllocator = @ptrCast(@alignCast(ctx));
        self.parent.rawFree(buf, ptr_align, ret_addr);

        if (enabled) {
            if (has_callstack) {
                ___tracy_emit_memory_free_callstack(@ptrCast(buf.ptr), callstack_depth, 1);
            } else {
                ___tracy_emit_memory_free(@ptrCast(buf.ptr), 1);
            }
        }
    }
};

threadlocal var message_buffer: [message_buffer_size]u8 = undefined;

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    if (enabled) {
        var stream = std.io.fixedBufferStream(&message_buffer);
        stream.writer().print(
            @tagName(scope) ++ "(" ++ @tagName(level) ++ "): " ++ format,
            args,
        ) catch {};

        const color = switch (level) {
            .debug => 0xd3d3d3,
            .info => 0x40a6ce,
            .warn => 0xf9e154,
            .err => 0xf02c2c,
        };

        const written = stream.getWritten();

        if (has_callstack) {
            ___tracy_emit_messageC(written.ptr, written.len, color, callstack_depth);
        } else {
            ___tracy_emit_messageC(written.ptr, written.len, color, 0);
        }
    }
}

pub fn startupProfiler() void {
    ___tracy_startup_profiler();
}

pub fn shutdownProfiler() void {
    ___tracy_shutdown_profiler();
}

extern fn ___tracy_alloc_srcloc(line: u32, source: [*]const u8, sourceSz: usize, function: [*]const u8, functionSz: usize) u64;
extern fn ___tracy_alloc_srcloc_name(line: u32, source: [*]const u8, sourceSz: usize, function: [*]const u8, functionSz: usize, name: [*]const u8, nameSz: usize) u64;

extern fn ___tracy_emit_zone_begin(srcloc: *const SourceLocationData, active: c_int) ZoneContext;
extern fn ___tracy_emit_zone_begin_callstack(srcloc: *const SourceLocationData, depth: c_int, active: c_int) ZoneContext;
extern fn ___tracy_emit_zone_begin_alloc(srcloc: u64, active: c_int) ZoneContext;
extern fn ___tracy_emit_zone_begin_alloc_callstack(srcloc: u64, depth: c_int, active: c_int) ZoneContext;

extern fn ___tracy_emit_frame_mark(name: ?[*:0]const u8) void;
extern fn ___tracy_emit_frame_mark_start(name: [*:0]const u8) void;
extern fn ___tracy_emit_frame_mark_end(name: [*:0]const u8) void;
extern fn ___tracy_emit_frame_image(image: ?*const anyopaque, w: u16, h: u16, offset: u8, flip: c_int) void;

extern fn ___tracy_emit_memory_alloc(ptr: ?*const anyopaque, size: usize, secure: c_int) void;
extern fn ___tracy_emit_memory_alloc_callstack(ptr: ?*const anyopaque, size: usize, depth: c_int, secure: c_int) void;
extern fn ___tracy_emit_memory_free(ptr: ?*const anyopaque, secure: c_int) void;
extern fn ___tracy_emit_memory_free_callstack(ptr: ?*const anyopaque, depth: c_int, secure: c_int) void;
extern fn ___tracy_emit_memory_alloc_named(ptr: ?*const anyopaque, size: usize, secure: c_int, name: [*c]const u8) void;
extern fn ___tracy_emit_memory_alloc_callstack_named(ptr: ?*const anyopaque, size: usize, depth: c_int, secure: c_int, name: [*c]const u8) void;
extern fn ___tracy_emit_memory_free_named(ptr: ?*const anyopaque, secure: c_int, name: [*c]const u8) void;
extern fn ___tracy_emit_memory_free_callstack_named(ptr: ?*const anyopaque, depth: c_int, secure: c_int, name: [*c]const u8) void;

extern fn ___tracy_emit_message(txt: [*]const u8, size: usize, callstack: c_int) void;
extern fn ___tracy_emit_messageL(txt: [*:0]const u8, callstack: c_int) void;
extern fn ___tracy_emit_messageC(txt: [*]const u8, size: usize, color: u32, callstack: c_int) void;
extern fn ___tracy_emit_messageLC(txt: [*:0]const u8, color: u32, callstack: c_int) void;

extern fn ___tracy_emit_plot(name: [*:0]const u8, val: f64) void;
extern fn ___tracy_emit_plot_float(name: [*:0]const u8, val: f32) void;
extern fn ___tracy_emit_plot_int(name: [*:0]const u8, val: i64) void;
extern fn ___tracy_emit_plot_config(name: [*:0]const u8, ty: c_int, step: c_int, fill: c_int, color: u32) void;

extern fn ___tracy_emit_gpu_zone_begin(GpuZoneBeginData) void;
extern fn ___tracy_emit_gpu_zone_begin_callstack(GpuZoneBeginCallstackData) void;
extern fn ___tracy_emit_gpu_zone_begin_alloc(GpuZoneBeginData) void;
extern fn ___tracy_emit_gpu_zone_begin_alloc_callstack(GpuZoneBeginCallstackData) void;
extern fn ___tracy_emit_gpu_zone_end(GpuZoneEndData) void;
extern fn ___tracy_emit_gpu_time(GpuTimeData) void;
extern fn ___tracy_emit_gpu_new_context(GpuNewContextData) void;
extern fn ___tracy_emit_gpu_context_name(GpuContextNameData) void;
extern fn ___tracy_emit_gpu_calibration(GpuCalibrationData) void;
extern fn ___tracy_emit_gpu_zone_begin_serial(GpuZoneBeginData) void;
extern fn ___tracy_emit_gpu_zone_begin_callstack_serial(GpuZoneBeginCallstackData) void;
extern fn ___tracy_emit_gpu_zone_begin_alloc_serial(GpuZoneBeginData) void;
extern fn ___tracy_emit_gpu_zone_begin_alloc_callstack_serial(GpuZoneBeginCallstackData) void;
extern fn ___tracy_emit_gpu_zone_end_serial(GpuZoneEndData) void;
extern fn ___tracy_emit_gpu_time_serial(GpuTimeData) void;
extern fn ___tracy_emit_gpu_new_context_serial(GpuNewContextData) void;
extern fn ___tracy_emit_gpu_context_name_serial(GpuContextNameData) void;
extern fn ___tracy_emit_gpu_calibration_serial(GpuCalibrationData) void;

extern fn ___tracy_set_thread_name(name: [*:0]const u8) void;
extern fn ___tracy_emit_message_appinfo(txt: [*c]const u8, size: usize) void;
extern fn ___tracy_connected() c_int;

extern fn ___tracy_startup_profiler() void;
extern fn ___tracy_shutdown_profiler() void;

extern fn ___tracy_fiber_enter(fiber: [*c]const u8) void;
extern fn ___tracy_fiber_leave() void;

test "all" {
    var tra = TracingAllocator.init(std.testing.allocator);
    const allocator = tra.allocator();

    for (0..200_000) |_| {
        frameMark();

        var ctx = zone(@src());
        ctx.end();

        frameMarkNamed("Frame2");

        ctx = zoneN(@src(), "Hello");
        ctx.end();

        ctx = zoneC(@src(), 0xffffff);
        ctx.end();

        ctx = zoneNC(@src(), "hello 2", 0xffeeaa);
        ctx.end();

        frameMarkStart("frame3");

        const mem = try allocator.alloc(u8, 100);
        const new_mem = try allocator.realloc(mem, 200);
        allocator.free(new_mem);

        logFn(.info, .testing, "hello ctx is {}", .{ctx});

        frameMarkEnd("frame3");
    }
}
