const std = @import("std");
const args_parser = @import("args");

const Mode = enum {
    compile, decompile
};

const Device = enum {
    pet2001,
    vc20,
    cbm3001,
    cbm3008,
    cbm3016,
    cbm3032,
    cbm4016,
    cbm4032,
    cbm8016,
    cbm8032,
    c64,
    c128,
    c16,
    c116,
    @"plus/4",
};

const Version = enum {
    @"1.0",
    @"2.0",
    @"3.5",
    @"4.0",
    @"7.0",
};

const CliArgs = struct {
    @"start-address": ?u16 = null,
    output: ?[]const u8 = null,
    help: bool = false,
    mode: Mode = .compile,
    device: ?Device = null,
    version: ?Version = null,

    pub const shortcuts = structs{
        .h = "help",
        .o = "output",
        .m = "mode",
        .d = "device",
        .v = "version",
    };
};

fn usage(app_name: []const u8, target: anytype) !void {
    try target.print("{s} [fileName]\n", .{app_name});
    try target.writeAll(
        \\Supported command line arguments:
        \\  -h, --help                 Prints this help text.
        \\      --start-address [num]  Defines the load address of the basic program. [num] is decimal (default) or hexadecimal (when prefixed).
        \\  -o, --output [file]        Sets the output file to [file] when given.
        \\  -m, --mode [mode]          Sets the mode to `compile` or `decompile`.
        \\  -d, --device [dev]         Sets the device. Supported devices are listed below.
        \\  -V, --version [vers]       Sets the used basic version. Supported basic versions are listed below.
        \\
        \\In `compile` mode, the application will read BASIC code from stdin or [fileName] when given and will tokenize it into a CBM readable format.
        \\Each line in the input must have a decimal line number followed by several characters. The input encoding is assumed to be PETSCII.
        \\
        \\In `decompile` mode the application will read in a BASIC PRG file and will output detokenized BASIC code.
        \\Each line in the output will be prefixed by a decimal line number and a space. The output encoding is assumed to be PETSCII.
        \\
        \\Supported devices:
        \\  c64, c128
        \\
        \\Supported BASIC versions:
        \\  1.0, 2.0, 3.5, 7.0
        \\
    );
}

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = &gpa.allocator;

    var cli = try args_parser.parseForCurrentProcess(CliArgs, allocator);
    defer cli.deinit();

    const app_name = std.fs.path.basename(cli.executable_name orelse @panic("requires executabe name!"));

    var stderr = std.io.getStdErr().writer();

    if (cli.positionals.len > 1) {
        try usage(app_name, stderr);
        return 1;
    }

    if (cli.options.help) {
        try usage(app_name, std.io.getStdOut().writer());
        return 0;
    }

    if (cli.options.device != null and cli.options.@"start-address" != null) {
        try stderr.writeAll("Cannot set --device and --start-address at the same time!\n");
        try usage(app_name, stderr);
        return 1;
    }

    if (cli.options.device == null) {
        cli.options.device = .c64;
    }
    std.debug.assert(cli.options.device != null);

    if (cli.options.@"start-address" == null) {
        cli.options.@"start-address" = switch (cli.options.device.?) {
            .c64 => 0x0801,
            .c128 => 0x1C01,
            .pet2001,
            .cbm3001,
            .cbm3008,
            .vc20,
            .cbm3016,
            .cbm3032,
            .c16,
            .c116,
            .@"plus/4",
            .cbm4016,
            .cbm4032,
            .cbm8016,
            .cbm8032,
            => {
                try stderr.print("{s} has no start address yet!\n", .{@tagName(cli.options.device.?)});
                return 1;
            },
        };
    }
    std.debug.assert(cli.options.@"start-address" != null);

    if (cli.options.version == null) {
        cli.options.version = switch (cli.options.device.?) {
            .pet2001 => .@"1.0",
            .cbm3001, .cbm3008 => .@"1.0",
            .vc20 => .@"2.0",
            .cbm3016, .cbm3032 => .@"2.0",
            .c64 => .@"2.0",
            .c16 => .@"3.5",
            .c116 => .@"3.5",
            .@"plus/4" => .@"3.5",
            .cbm4016, .cbm4032 => .@"4.0",
            .cbm8016, .cbm8032 => .@"4.0",
            .c128 => .@"7.0",
        };
    }
    std.debug.assert(cli.options.version != null);

    const tokens: []const Token = switch (cli.options.version.?) {
        .@"1.0" => &tokens_1_0,
        .@"2.0" => &tokens_2_0,
        .@"3.5" => &tokens_3_5,
        .@"4.0" => {
            try stderr.writeAll("BASIC V4 supported not implemented yet!\n");
            return 1;
        },
        .@"7.0" => &tokens_7_0,
    };

    switch (cli.options.mode) {
        .compile => {
            var input_file: std.fs.File = if (cli.positionals.len > 0 and !std.mem.eql(u8, "-", cli.positionals[0]))
                try std.fs.cwd().openFile(cli.positionals[0], .{})
            else
                std.io.getStdIn();
            defer if (cli.positionals.len > 0)
                input_file.close();

            var output_file: std.fs.File = if (cli.options.output) |out|
                try std.fs.cwd().createFile(out, .{})
            else
                std.io.getStdOut();

            errdefer if (cli.options.output) |out| {
                std.fs.cwd().deleteFile(out) catch std.debug.panic("failed to delete {s}", .{out});
            };

            defer if (cli.options.output) |out| {
                output_file.close();
            };

            try compileBasic(allocator, input_file.reader(), output_file.writer(), DeviceInfo{
                .start_address = cli.options.@"start-address".?,
                .tokens = tokens,
            });
        },

        .decompile => {
            @panic("not implemented yet!");
        },
    }

    return 0;
}

const DeviceInfo = struct {
    start_address: u16,
    tokens: []const Token,
};

fn compileBasic(allocator: *std.mem.Allocator, input_stream: anytype, output_stream: anytype, device: DeviceInfo) !void {
    const Line = struct {
        number: u16,
        tokens: []u8,
    };

    var lines = std.ArrayList(Line).init(allocator);
    defer lines.deinit();

    var string_arena = std.heap.ArenaAllocator.init(allocator);
    defer string_arena.deinit();

    {
        var line_buffer: [1024]u8 = undefined;

        while (true) {
            const buffer = (try input_stream.readUntilDelimiterOrEof(&line_buffer, '\n')) orelse break;

            const spc_index = std.mem.indexOf(u8, buffer, " ") orelse return error.MissingLineNumber;
            const number = try std.fmt.parseInt(u16, buffer[0..spc_index], 10);

            var line = buffer[spc_index + 1 ..];
            while (line.len > 0 and line[0] == ' ') {
                line = line[1..];
            }

            var translated_storage: [250]u8 = undefined;

            var translate_stream = std.io.fixedBufferStream(&translated_storage);

            var out_stream = translate_stream.writer();

            var input_offset: usize = 0;
            var reading_string = false;
            while (input_offset < line.len) {
                const rest = line[input_offset..];

                const token: ?Token = if (reading_string)
                    null // no tokenization in strings
                else for (device.tokens) |tok| {
                    if (std.mem.startsWith(u8, rest, tok.text)) {
                        break tok;
                    }
                } else null;

                if (token) |tok| {
                    try out_stream.writeAll(tok.sequence);
                    input_offset += tok.text.len;
                } else {
                    const c = line[input_offset];
                    try out_stream.writeByte(c);
                    input_offset += 1;

                    if (c == '\"')
                        reading_string = !reading_string;
                }
            }

            try lines.append(Line{
                .number = number,
                .tokens = try string_arena.allocator.dupe(u8, translate_stream.getWritten()),
            });
        }
    }

    {
        var start_offset: u16 = device.start_address;

        try output_stream.writeIntLittle(u16, start_offset);
        for (lines.items) |line| {
            start_offset += @intCast(u16, 0x05 + 0x01 + line.tokens.len);

            try output_stream.writeIntLittle(u16, start_offset);
            try output_stream.writeIntLittle(u16, line.number);
            try output_stream.writeAll(line.tokens);
            try output_stream.writeByte(0);
        }

        // Write "END OF FILE"
        try output_stream.writeAll(&[_]u8{ 0x00, 0x00, 0x00 });
    }
}

const Token = struct {
    const Self = @This();

    text: []const u8,
    sequence: []const u8,

    fn compareText(ctx: void, lhs: Self, rhs: Self) bool {
        return std.mem.order(u8, lhs.text, rhs.text) == .lt;
    }

    fn compareSequence(ctx: void, lhs: Self, rhs: Self) bool {
        return std.mem.order(u8, lhs.text, rhs.text) == .lt;
    }
};

fn sortTokens(tokens: anytype) @TypeOf(tokens) {
    var mut = tokens;
    @setEvalBranchQuota(tokens.len * tokens.len);
    std.sort.sort(Token, &mut, {}, Token.compareText);
    return mut;
}

const tokens_1_0 = sortTokens([_]Token{
    Token{ .text = "END", .sequence = "\x80" },
    Token{ .text = "FOR", .sequence = "\x81" },
    Token{ .text = "NEXT", .sequence = "\x82" },
    Token{ .text = "DATA", .sequence = "\x83" },
    Token{ .text = "INPUT#", .sequence = "\x84" },
    Token{ .text = "INPUT", .sequence = "\x85" },
    Token{ .text = "DIM", .sequence = "\x86" },
    Token{ .text = "READ", .sequence = "\x87" },
    Token{ .text = "LET", .sequence = "\x88" },
    Token{ .text = "GOTO", .sequence = "\x89" },
    Token{ .text = "RUN", .sequence = "\x8a" },
    Token{ .text = "IF", .sequence = "\x8b" },
    Token{ .text = "RESTORE", .sequence = "\x8c" },
    Token{ .text = "GOSUB", .sequence = "\x8d" },
    Token{ .text = "RETURN", .sequence = "\x8e" },
    Token{ .text = "REM", .sequence = "\x8f" },
    Token{ .text = "STOP", .sequence = "\x90" },
    Token{ .text = "ON", .sequence = "\x91" },
    Token{ .text = "WAIT", .sequence = "\x92" },
    Token{ .text = "LOAD", .sequence = "\x93" },
    Token{ .text = "SAVE", .sequence = "\x94" },
    Token{ .text = "VERIFY", .sequence = "\x95" },
    Token{ .text = "DEF", .sequence = "\x96" },
    Token{ .text = "POKE", .sequence = "\x97" },
    Token{ .text = "PRINT#", .sequence = "\x98" },
    Token{ .text = "PRINT", .sequence = "\x99" },
    Token{ .text = "CONT", .sequence = "\x9a" },
    Token{ .text = "LIST", .sequence = "\x9b" },
    Token{ .text = "CLR", .sequence = "\x9c" },
    Token{ .text = "CMD", .sequence = "\x9d" },
    Token{ .text = "SYS", .sequence = "\x9e" },
    Token{ .text = "OPEN", .sequence = "\x9f" },
    Token{ .text = "CLOSE", .sequence = "\xa0" },
    Token{ .text = "GET", .sequence = "\xa1" },
    Token{ .text = "NEW", .sequence = "\xa2" },
    Token{ .text = "TAB", .sequence = "\xa3" },
    Token{ .text = "TO", .sequence = "\xa4" },
    Token{ .text = "FN", .sequence = "\xa5" },
    Token{ .text = "SPC", .sequence = "\xa6" },
    Token{ .text = "THEN", .sequence = "\xa7" },
    Token{ .text = "NOT", .sequence = "\xa8" },
    Token{ .text = "STEP", .sequence = "\xa9" },
    Token{ .text = "+", .sequence = "\xaa" },
    Token{ .text = "-", .sequence = "\xab" },
    Token{ .text = "*", .sequence = "\xac" },
    Token{ .text = "/", .sequence = "\xad" },
    Token{ .text = "^", .sequence = "\xae" },
    Token{ .text = "AND", .sequence = "\xaf" },
    Token{ .text = "OR", .sequence = "\xb0" },
    Token{ .text = ">", .sequence = "\xb1" },
    Token{ .text = "=", .sequence = "\xb2" },
    Token{ .text = "<", .sequence = "\xb3" },
    Token{ .text = "SGN", .sequence = "\xb4" },
    Token{ .text = "INT", .sequence = "\xb5" },
    Token{ .text = "ABS", .sequence = "\xb6" },
    Token{ .text = "USR", .sequence = "\xb7" },
    Token{ .text = "FRE", .sequence = "\xb8" },
    Token{ .text = "POS", .sequence = "\xb9" },
    Token{ .text = "SQR", .sequence = "\xba" },
    Token{ .text = "RND", .sequence = "\xbb" },
    Token{ .text = "LOG", .sequence = "\xbc" },
    Token{ .text = "EXP", .sequence = "\xbd" },
    Token{ .text = "COS", .sequence = "\xbe" },
    Token{ .text = "SIN", .sequence = "\xbf" },
    Token{ .text = "TAN", .sequence = "\xc0" },
    Token{ .text = "ATN", .sequence = "\xc1" },
    Token{ .text = "PEEK", .sequence = "\xc2" },
    Token{ .text = "LEN", .sequence = "\xc3" },
    Token{ .text = "STR", .sequence = "\xc4" },
    Token{ .text = "VAL", .sequence = "\xc5" },
    Token{ .text = "ASC", .sequence = "\xc6" },
    Token{ .text = "CHR", .sequence = "\xc7" },
    Token{ .text = "LEFT", .sequence = "\xc8" },
    Token{ .text = "RIGHT", .sequence = "\xc9" },
    Token{ .text = "MID$", .sequence = "\xca" },
});

const tokens_2_0 = sortTokens(tokens_1_0 ++ [_]Token{
    Token{ .text = "GO", .sequence = "\xcb" },
});

const tokens_3_5 = sortTokens(tokens_2_0 ++ [_]Token{
    Token{ .text = "RGR", .sequence = "\xcc" },
    Token{ .text = "RCLR", .sequence = "\xcd" },
    Token{ .text = "RLUM", .sequence = "\xce" },
    Token{ .text = "JOY", .sequence = "\xcf" },
    Token{ .text = "RDOT", .sequence = "\xd0" },
    Token{ .text = "DEC", .sequence = "\xd1" },
    Token{ .text = "HEX", .sequence = "\xd2" },
    Token{ .text = "ERR", .sequence = "\xd3" },
    Token{ .text = "INSTR", .sequence = "\xd4" },
    Token{ .text = "ELSE", .sequence = "\xd5" },
    Token{ .text = "RESUME", .sequence = "\xd6" },
    Token{ .text = "TRAP", .sequence = "\xd7" },
    Token{ .text = "TRON", .sequence = "\xd8" },
    Token{ .text = "TROFF", .sequence = "\xd9" },
    Token{ .text = "SOUND", .sequence = "\xda" },
    Token{ .text = "VOL", .sequence = "\xdb" },
    Token{ .text = "AUTO", .sequence = "\xdc" },
    Token{ .text = "PUDEF", .sequence = "\xdd" },
    Token{ .text = "GRAPHIC", .sequence = "\xde" },
    Token{ .text = "PAINT", .sequence = "\xdf" },
    Token{ .text = "CHAR", .sequence = "\xe0" },
    Token{ .text = "BOX", .sequence = "\xe1" },
    Token{ .text = "CIRCLE", .sequence = "\xe2" },
    Token{ .text = "GSHAPE", .sequence = "\xe3" },
    Token{ .text = "SSHAPE", .sequence = "\xe4" },
    Token{ .text = "DRAW", .sequence = "\xe5" },
    Token{ .text = "LOCATE", .sequence = "\xe6" },
    Token{ .text = "COLOR", .sequence = "\xe7" },
    Token{ .text = "SCNCLR", .sequence = "\xe8" },
    Token{ .text = "SCALE", .sequence = "\xe9" },
    Token{ .text = "HELP", .sequence = "\xea" },
    Token{ .text = "DO", .sequence = "\xeb" },
    Token{ .text = "LOOP", .sequence = "\xec" },
    Token{ .text = "EXIT", .sequence = "\xed" },
    Token{ .text = "DIRECTORY", .sequence = "\xee" },
    Token{ .text = "DSAVE", .sequence = "\xef" },
    Token{ .text = "DLOAD", .sequence = "\xf0" },
    Token{ .text = "HEADER", .sequence = "\xf1" },
    Token{ .text = "SCRATCH", .sequence = "\xf2" },
    Token{ .text = "COLLECT", .sequence = "\xf3" },
    Token{ .text = "COPY", .sequence = "\xf4" },
    Token{ .text = "RENAME", .sequence = "\xf5" },
    Token{ .text = "BACKUP", .sequence = "\xf6" },
    Token{ .text = "DELETE", .sequence = "\xf7" },
    Token{ .text = "RENUMBER", .sequence = "\xf8" },
    Token{ .text = "KEY", .sequence = "\xf9" },
    Token{ .text = "MONITOR", .sequence = "\xfa" },
    Token{ .text = "USING", .sequence = "\xfb" },
    Token{ .text = "UNTIL", .sequence = "\xfc" },
    Token{ .text = "WHILE", .sequence = "\xfd" },
});

const tokens_7_0 = sortTokens(tokens_3_5 ++ [_]Token{
    // 0xCE …
    Token{ .text = "POT", .sequence = "\xce\x02" },
    Token{ .text = "BUMP", .sequence = "\xce\x03" },
    Token{ .text = "PEN", .sequence = "\xce\x04" },
    Token{ .text = "RSPPOS", .sequence = "\xce\x05" },
    Token{ .text = "RSPRITE", .sequence = "\xce\x06" },
    Token{ .text = "RSPCOLOR", .sequence = "\xce\x07" },
    Token{ .text = "XOR", .sequence = "\xce\x08" },
    Token{ .text = "RWINDOW", .sequence = "\xce\x09" },
    Token{ .text = "POINTER", .sequence = "\xce\x0a" },
    // 0xFE …
    Token{ .text = "BANK", .sequence = "\xfe\x02" },
    Token{ .text = "FILTER", .sequence = "\xfe\x03" },
    Token{ .text = "PLAY", .sequence = "\xfe\x04" },
    Token{ .text = "TEMPO", .sequence = "\xfe\x05" },
    Token{ .text = "MOVSPR", .sequence = "\xfe\x06" },
    Token{ .text = "SPRITE", .sequence = "\xfe\x07" },
    Token{ .text = "SPRCOLOR", .sequence = "\xfe\x08" },
    Token{ .text = "RREG", .sequence = "\xfe\x09" },
    Token{ .text = "ENVELOPE", .sequence = "\xfe\x0a" },
    Token{ .text = "SLEEP", .sequence = "\xfe\x0b" },
    Token{ .text = "CATALOG", .sequence = "\xfe\x0c" },
    Token{ .text = "DOPEN", .sequence = "\xfe\x0d" },
    Token{ .text = "APPEND", .sequence = "\xfe\x0e" },
    Token{ .text = "DCLOSE", .sequence = "\xfe\x0f" },
    Token{ .text = "BSAVE", .sequence = "\xfe\x10" },
    Token{ .text = "BLOAD", .sequence = "\xfe\x11" },
    Token{ .text = "RECORD", .sequence = "\xfe\x12" },
    Token{ .text = "CONCAT", .sequence = "\xfe\x13" },
    Token{ .text = "DVERIFY", .sequence = "\xfe\x14" },
    Token{ .text = "DCLEAR", .sequence = "\xfe\x15" },
    Token{ .text = "SPRSAV", .sequence = "\xfe\x16" },
    Token{ .text = "COLLISION", .sequence = "\xfe\x17" },
    Token{ .text = "BEGIN", .sequence = "\xfe\x18" },
    Token{ .text = "BEND", .sequence = "\xfe\x19" },
    Token{ .text = "WINDOW", .sequence = "\xfe\x1a" },
    Token{ .text = "BOOT", .sequence = "\xfe\x1b" },
    Token{ .text = "WIDTH", .sequence = "\xfe\x1c" },
    Token{ .text = "SPRDEF", .sequence = "\xfe\x1d" },
    Token{ .text = "QUIT", .sequence = "\xfe\x1e" },
    Token{ .text = "STASH", .sequence = "\xfe\x1f" },
    Token{ .text = "FETCH", .sequence = "\xfe\x21" },
    Token{ .text = "SWAP", .sequence = "\xfe\x23" },
    Token{ .text = "OFF", .sequence = "\xfe\x24" },
    Token{ .text = "FAST", .sequence = "\xfe\x25" },
    Token{ .text = "SLOW", .sequence = "\xfe\x26" },
});

test "empty program" {
    var output_buffer: [4096]u8 = undefined;
    var output_stream = std.io.fixedBufferStream(&output_buffer);

    try compileBasic(
        std.testing.allocator,
        std.io.fixedBufferStream("").reader(),
        output_stream.writer(),
        DeviceInfo{
            .start_address = 0x1234,
            .tokens = &tokens_1_0,
        },
    );

    std.testing.expectEqualSlices(u8, "\x34\x12\x00\x00\x00", output_stream.getWritten());
}

test "10 INPUT I" {
    var output_buffer: [4096]u8 = undefined;
    var output_stream = std.io.fixedBufferStream(&output_buffer);

    try compileBasic(
        std.testing.allocator,
        std.io.fixedBufferStream("10 INPUT I").reader(),
        output_stream.writer(),
        DeviceInfo{
            .start_address = 0x0000,
            .tokens = &tokens_1_0,
        },
    );

    std.testing.expectEqualSlices(
        u8,
        "\x00\x00" ++ // start address
            "\x09\x00\x0A\x00\x85 I\x00" ++ // 10 INPUT I
            "\x00\x00\x00", // terminator
        output_stream.getWritten(),
    );
}

test "multiple lines" {
    var output_buffer: [4096]u8 = undefined;
    var output_stream = std.io.fixedBufferStream(&output_buffer);

    try compileBasic(
        std.testing.allocator,
        std.io.fixedBufferStream(
            \\10 INPUT I
            \\20 PRINT "HALLO"
        ).reader(),
        output_stream.writer(),
        DeviceInfo{
            .start_address = 0x0000,
            .tokens = &tokens_1_0,
        },
    );

    std.testing.expectEqualSlices(
        u8,
        "\x00\x00" ++ // start address
            "\x09\x00\x0A\x00\x85 I\x00" ++ // 10 INPUT I
            "\x18\x00\x14\x00\x99 \"HALLO\"\x00" ++ // 20 PRINT "HALLO"
            "\x00\x00\x00", // terminator
        output_stream.getWritten(),
    );
}
