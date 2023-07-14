const std = @import("std");

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // don't forget to flush!
}

pub const Poly = struct {
    a: u8,
    b: u8,
    c: u8,
    set: std.DynamicBitSet,

    const Self = @This();

    fn initEmpty(alloc: std.mem.Allocator, a: u8, b: u8, c: u8) !Self {
        return Self{
            .a = a,
            .b = b,
            .c = c,
            .set = try std.DynamicBitSet.initEmpty(alloc, a * b * c),
        };
    }

    pub fn idx(a: u8, b: u8, c: u8) usize {
        return a << 16 + b << 8 + c;
    }

    fn deinit(self: *Self) void {
        self.set.deinit();
    }

    fn hash(self: Self) u64 {
        var hasher = Wyhash.init(0);
        hasher.update(std.mem.asBytes(&self.a));
        hasher.update(std.mem.asBytes(&self.b));
        hasher.update(std.mem.asBytes(&self.c));
        hash_bitset_into(self.set.unmanaged, &hasher);
        return hasher.final();
    }

    fn eql(self: Self, other: Self) bool {
        if (self.a != other.a or self.b != other.b or self.c != other.c) {
            return false;
        }
        return bitsets_eql(self.set, other.set);
    }

    fn clone(self: Self, alloc: std.mem.Allocator) !Self {
        return Self{
            .a = self.a,
            .b = self.b,
            .c = self.c,
            .set = try self.set.clone(alloc),
        };
    }
};

var STRESS_TEST: bool = true;
var STRESS_COUNT: usize = 100; // 1000000;
test "map + hash stress test" {
    if (!STRESS_TEST) {
        return error.SkipZigTest;
    }
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var polys = HashSet.init(alloc);
    defer polys.deinit();

    const n: usize = 2;
    var p = try Poly.initEmpty(alloc, n, n, n);
    defer p.deinit();

    var combination: usize = 0;
    while (combination < STRESS_COUNT) : (combination += 1) {
        // std.log.warn("combination {}", .{combination});
        var bit: u4 = 0;
        while (bit <= 7) : (bit += 1) {
            var value = (combination & (@as(u8, 1) << @truncate(u3, bit))) > 0;
            p.set.setValue(bit, value);
            // std.log.warn("bit {}: {}", .{ bit, value });
        }
        var gop = try polys.getOrPut(p);
        if (!gop.found_existing) {
            gop.key_ptr.* = try p.clone(alloc);
        }
    }

    std.log.warn("{} polys", .{polys.count()});
}

pub const MapContext = struct {
    const Self = @This();
    pub fn eql(self: Self, a: Poly, b: Poly) bool {
        _ = self;
        return a.eql(b);
    }
    pub fn hash(self: Self, val: Poly) u64 {
        _ = self;
        return val.hash();
    }
};
const HashSet = std.HashMap(Poly, void, MapContext, std.hash_map.default_max_load_percentage);

test "map usage" {
    const t = std.testing;
    const alloc = t.allocator;

    var polys = HashSet.init(alloc);
    defer polys.deinit();

    var p = try Poly.initEmpty(alloc, 2, 1, 1);
    defer p.deinit();
    p.set.set(0);

    try t.expectEqual(polys.count(), 0);
    try polys.put(p, {});
    try t.expectEqual(polys.count(), 1);
    try polys.put(p, {});
    try t.expectEqual(polys.count(), 1);

    var p2 = try Poly.initEmpty(alloc, 2, 1, 1);
    defer p2.deinit();
    p2.set.set(0);
    try polys.put(p2, {});
    try t.expectEqual(polys.count(), 1);

    // same volume, but different dimensions
    var p3 = try Poly.initEmpty(alloc, 1, 1, 2);
    defer p3.deinit();
    p3.set.set(0);
    try polys.put(p3, {});
    try t.expectEqual(polys.count(), 2);

    p3.set.set(1);
    try polys.put(p3, {});
    try t.expectEqual(polys.count(), 3);
}

fn numMasks(bit_length: usize) usize {
    return (bit_length + (@bitSizeOf(usize) - 1)) / @bitSizeOf(usize);
}

const Wyhash = std.hash.Wyhash;
fn hash_bitset(s: std.DynamicBitSetUnmanaged) u64 {
    var hasher = Wyhash.init(0);

    hash_bitset_into(s, &hasher);

    return hasher.final();
}
fn hash_bitset_into(s: std.DynamicBitSetUnmanaged, hasher: *Wyhash) void {
    hasher.update(std.mem.asBytes(&s.bit_length));
    for (s.masks[0..numMasks(s.bit_length)]) |*m| {
        hasher.update(std.mem.asBytes(m));
    }
}

test "hashing bitsets" {
    const t = std.testing;
    const alloc = t.allocator;

    var a = try std.DynamicBitSet.initEmpty(alloc, 65);
    defer a.deinit();
    var b = try std.DynamicBitSet.initEmpty(alloc, 65);
    defer b.deinit();
    var c = try std.DynamicBitSet.initEmpty(alloc, 66);
    defer c.deinit();

    try t.expectEqual(
        hash_bitset(a.unmanaged),
        hash_bitset(b.unmanaged),
    );
    try t.expect(hash_bitset(a.unmanaged) != hash_bitset(c.unmanaged));

    a.set(2);
    b.set(2);
    c.set(2);
    try t.expectEqual(
        hash_bitset(a.unmanaged),
        hash_bitset(b.unmanaged),
    );
    try t.expect(hash_bitset(a.unmanaged) != hash_bitset(c.unmanaged));
}

pub fn bitsets_eql(a: std.DynamicBitSet, b: std.DynamicBitSet) bool {
    if (a.capacity() != b.capacity()) {
        return false;
    }
    var a_it = a.iterator(.{});
    var b_it = b.iterator(.{});

    while (true) {
        var an = a_it.next();
        var bn = b_it.next();
        if (an != bn) {
            return false;
        }
        if (an == null or bn == null) {
            break;
        }
    }
    return true;
}

test "bitset equality" {
    const t = std.testing;
    const alloc = t.allocator;

    var a = try std.DynamicBitSet.initEmpty(alloc, 4);
    defer a.deinit();
    var b = try std.DynamicBitSet.initEmpty(alloc, 4);
    defer b.deinit();
    var c = try std.DynamicBitSet.initEmpty(alloc, 5);
    defer c.deinit();

    try t.expect(bitsets_eql(a, b));
    try t.expect(!bitsets_eql(a, c));

    a.set(0);
    try t.expect(!bitsets_eql(a, b));
}
