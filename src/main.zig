const std = @import("std");

const decoderError = error{
    NotPng,
    EndOfFile,
};

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

// convert all struct fields into native endian from Big Endian
fn toNativeStructEndian(t: anytype) @TypeOf(t) {
    switch (@typeInfo(@TypeOf(t))) {
        .@"struct" => |st| {
            var result: @TypeOf(t) = undefined;
            inline for (st.fields) |field| {
                @field(result, field.name) = toNativeStructEndian(@field(t, field.name));
            }
            return result;
        },
        .int => {
            return std.mem.bigToNative(@TypeOf(t), t);
        },
        else => @compileError("Can't handle endian swap of" ++ @typeName(t)),
    }
}

// define the chunk layout
const ChunkLayout = struct {
    length: usize,
    type: []const u8,
    data: []const u8,
    crc: []const u8,

    fn isCritical(self: ChunkLayout) bool {
        return std.ascii.isUpper(self.type[0]);
    }

    fn parsedHeader(self: ChunkLayout) ChunkData {
        const getParsedType = std.meta.stringToEnum(ChunkType, self.type) orelse return .{ .unknown = self.data };

        switch (getParsedType) {
            .IHDR => {
                return .{ .IHDR = toNativeStructEndian(std.mem.bytesToValue(IHDR, self.data)) };
            },
            .unknown => {
                return .{ .unknown = self.data };
            },
        }
    }
};

const IHDR = packed struct {
    width: u32,
    height: u32,
    bit_depth: u8,
    color_type: u8,
    compression_method: u8,
    filter_method: u8,
    interlace_method: u8,
};

const ChunkType = enum {
    IHDR,
    unknown,
};

const ChunkData = union(ChunkType) { IHDR: IHDR, unknown: []const u8 };

const PngDecoder = struct {
    data: []const u8,
    index: usize = 8, // Just trying something
    complete: bool = false,

    fn init(data: []const u8) !PngDecoder {
        if (!isPng(data)) {
            return decoderError.NotPng;
        }

        return .{ .data = data };
    }

    fn nextChunk(self: *PngDecoder) !?ChunkLayout {
        if (self.complete == true) {
            return null;
        }

        const bytes = try self.advanceChunk(4);
        const length = std.mem.bigToNative(u32, std.mem.bytesToValue(u32, bytes));

        const chunk_type = try self.advanceChunk(4);
        if (std.mem.eql(u8, "IEND", chunk_type)) {
            self.complete = true;
        }

        return .{ .length = length, .type = chunk_type, .data = try self.advanceChunk(length), .crc = try self.advanceChunk(4) };
    }

    fn advanceChunk(self: *PngDecoder, length: usize) ![]const u8 {
        if (self.index + length > self.data.len) {
            return decoderError.EndOfFile;
        }

        defer self.index += length;
        return self.data[self.index .. self.index + length];
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const alloc = gpa.allocator();

    // FIXME: CLI input based?
    const png = try std.fs.cwd().openFile("sad_face.png", .{});
    defer png.close();

    const data = try png.readToEndAlloc(alloc, 1 * 1024 * 1024);
    defer alloc.free(data);

    var decoder = try PngDecoder.init(data);

    while (try decoder.nextChunk()) |chunk| {
        if (chunk.isCritical()) {
            std.debug.print("Chunk Type: {s}\nChunk Length: {}\n", .{ chunk.type, chunk.length });
            switch (chunk.parsedHeader()) {
                .IHDR => |d| {
                    std.debug.print("Header: {}\n", .{d});
                },
                .unknown => {},
            }
        }
    }
}
