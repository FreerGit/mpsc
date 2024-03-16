const std = @import("std");
const assert = std.debug.assert;

pub const cache_line_length = std.atomic.cache_line;

pub fn Mpsc(comptime T: type) type {
    return struct {
        pub const Node = struct {
            next: ?*Node = null,
            value: T,
        };

        // No mom it's not a "messy pile of clothes on my chair" it's an L1 cache for fast
        // random access to my frequently used clothes in O(1) time. it needs to be big to avoid expensive
        // cache misses (looking in my closet). I NEED to be minimizing latency, this is important to me. Please.
        //  - @0xAsync
        front: Node align(cache_line_length) = .{ .value = undefined },
        count: usize align(cache_line_length) = 0,
        back: ?*Node align(cache_line_length) = null,

        // Highly recommend reading https://dev.to/kprotty/understanding-atomics-and-memory-ordering-2mom
        // For a good understanding of the atomic operations here!
        pub fn peek(self: *const Mpsc(T)) usize {
            const count = @atomicLoad(usize, &self.count, .monotonic);
            assert(count >= 0);
            return count;
        }

        pub fn try_push(self: *Mpsc(T), src: *Node) void {
            assert(@atomicRmw(usize, &self.count, .Add, 1, .monotonic) >= 0);
            src.next = null;
            const old = @atomicRmw(?*Node, &self.back, .Xchg, src, .acq_rel) orelse &self.front;
            @atomicStore(?*Node, &old.next, src, .release);
        }

        pub fn try_pop(self: *Mpsc(T)) !?*Node {
            var first = @atomicLoad(?*Node, &self.front.next, .acquire) orelse return null;

            if (@atomicLoad(?*Node, &first.next, .acquire)) |next| {
                self.front.next = next;
                assert(@atomicRmw(usize, &self.count, .Sub, 1, .monotonic) >= 1);
                return first;
            }

            const last = @atomicLoad(?*Node, &self.back, .acquire) orelse &self.front;
            if (first != last) return null;

            self.front.next = null;

            if (@cmpxchgStrong(?*Node, &self.back, last, &self.front, .acq_rel, .acquire) == null) {
                assert(@atomicRmw(usize, &self.count, .Sub, 1, .monotonic) >= 1);
                return first;
            }

            var maybe_next = @atomicLoad(?*Node, &first.next, .acquire);
            while (maybe_next == null) : (try std.Thread.yield()) {
                maybe_next = @atomicLoad(?*Node, &first.next, .acquire);
            }

            self.front.next = maybe_next;

            assert(@atomicRmw(usize, &self.count, .Sub, 1, .monotonic) >= 1);
            return first;
        }
    };
}

test "Illustrate the size of Node" {
    const A = struct {
        a: i64,
        b: i64,
        c: i64,
    };

    // Be cognizant of changes.
    try std.testing.expectEqual(@sizeOf(Mpsc(i64).Node), 16);
    // We store one value which changes the size of the struct and another pointer which is 8 bytes.
    try std.testing.expectEqual(@sizeOf(Mpsc(i32).Node), 16);
    try std.testing.expectEqual(@sizeOf(Mpsc(u8).Node), 16);
    try std.testing.expectEqual(@sizeOf(Mpsc(bool).Node), 16);
    // Using a more complex type will produce larger Node size, again just be cognizant.
    try std.testing.expectEqual(@sizeOf(Mpsc(A).Node), 32);
}

test "Illustrate the size of Mpsc" {
    // Again, just like the test above, this doesn't change unless the implementation changes
    // It's more to illustrate the point of cache effiency and to be cognizant memory layout.
    switch (cache_line_length) {
        32 => try std.testing.expectEqual(@sizeOf(Mpsc(i64)), 96),
        64 => try std.testing.expectEqual(@sizeOf(Mpsc(i64)), 192),
        128 => try std.testing.expectEqual(@sizeOf(Mpsc(i64)), 384),
        256 => try std.testing.expectEqual(@sizeOf(Mpsc(i64)), 768),
        else => unreachable,
    }
}

test "Trivial peek" {
    var queue: Mpsc(i64) = .{};
    try std.testing.expect(queue.peek() == 0);
}

test "Trivial push and pop" {
    var queue: Mpsc(u64) = .{};
    const allocator = std.testing.allocator;

    for (0..10) |i| {
        const node = try allocator.create(Mpsc(u64).Node);
        node.* = .{ .value = @intCast(i) };
        queue.try_push(node);
    }

    for (0..10) |_| {
        if (try queue.try_pop()) |node| {
            allocator.destroy(node);
        }
    }

    try std.testing.expectEqual(queue.peek(), 0);
}

test "push and pop 100_000 u64s with 10 producers" {
    const NUM_ITEMS = 100_000;
    const NUM_PRODUCERS = 10;

    var queue: Mpsc(u64) = .{};
    const allocator = std.testing.allocator;

    const fns = struct {
        fn runProducer(q: *Mpsc(u64)) !void {
            for (0..NUM_ITEMS / NUM_PRODUCERS) |i| {
                const node = try allocator.create(Mpsc(u64).Node);
                node.* = .{ .value = @intCast(i) };
                q.try_push(node);
            }
        }

        fn runConsumer(q: *Mpsc(u64)) !void {
            for (0..NUM_ITEMS) |_| {
                while (true) {
                    if (try q.try_pop()) |node| {
                        allocator.destroy(node);
                        break;
                    }
                }
            }
        }
    };

    const consumer = try std.Thread.spawn(.{}, fns.runConsumer, .{&queue});

    var producers: [NUM_PRODUCERS]std.Thread = undefined;

    for (&producers) |*producer| {
        producer.* = try std.Thread.spawn(.{}, fns.runProducer, .{&queue});
    }

    const begin = std.time.nanoTimestamp();
    consumer.join();
    for (producers) |producer| producer.join();
    const end = std.time.nanoTimestamp();
    std.debug.print("{d}\n", .{end - begin});
    try std.testing.expect(queue.peek() == 0);
}
