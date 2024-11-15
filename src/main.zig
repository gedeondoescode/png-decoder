const std = @import("std");

// Check if the image is a PNG
fn isPng(data: []const u8) bool {

    // Make the first 8 bytes a single integer for easier access
    const png_sig: u64 = 0x89504e470d0a1a0a;
    const sig_value = std.mem.bytesToValue(u64, &png_sig);

    var data_value: u64 = 0;

    // Squish down the array into a single integer, similar to png_sig
    for (data[0..8]) |byte| {
        data_value = (data_value << 8) | byte;
    }

    // if the first 8 bytes don't match just ensure it's false since it's
    // most likely not a PNG
    if (data_value != sig_value) {
        return false;
    }

    // Finally, return true if they match
    return sig_value == data_value;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const alloc = gpa.allocator();

    const png = try std.fs.cwd().openFile("screenshots.avif", .{});
    defer png.close();

    const data = try png.readToEndAlloc(alloc, 1 * 1024 * 1024);
    defer alloc.free(data);

    std.debug.print("Is a PNG: {}\n", .{isPng(data)});
}
