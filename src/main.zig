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

// pub enum AbsAxis {
//     X,
//     Y,
//     Z,
// }
// pub enum CharacteristicAxi {
//     Major,
//     Middle,
//     Minor,
// }

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
};

// test "map + hash stress test" {
//     const t = std.testing;
//     const alloc = t.allocator;
//
//     const n: usize = 4;
//
//     var p = Poly.initEmpty(alloc, n, n, n);
//
//     var i: usize = 0;
//     while (kkkkkkk
//
//     try t.expect(false);
// }

pub const MapContext = struct {
    const Self = @This();
    pub fn eql(self: Self, a: Poly, b: Poly) bool {
        _ = self;
        if (a.a != b.a or a.b != b.b or a.c != b.c) {
            return false;
        }
        return bitsets_eql(a.set, b.set);
    }
    pub fn hash(self: Self, val: Poly) u64 {
        _ = self;
        return hash_bitset(val.set.unmanaged);
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
}

fn numMasks(bit_length: usize) usize {
    return (bit_length + (@bitSizeOf(usize) - 1)) / @bitSizeOf(usize);
}

const Wyhash = std.hash.Wyhash;
fn hash_bitset(s: std.DynamicBitSetUnmanaged) u64 {
    var hasher = Wyhash.init(0);

    hasher.update(std.mem.asBytes(&s.bit_length));

    for (s.masks[0..numMasks(s.bit_length)]) |*m| {
        hasher.update(std.mem.asBytes(m));
    }

    return hasher.final();
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
