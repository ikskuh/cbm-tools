const std = @import("std");
const args_parser = @import("args");

const Mode = enum {
    compile, decompile
};

const Device = enum {
    c64,
    c128,
};

const CliArgs = struct {
    @"start-address": ?u16 = null,
    output: ?[]const u8 = null,
    help: bool = false,
    mode: Mode = .compile,
    device: ?Device = null,

    pub const shortcuts = structs{
        .h = "help",
        .o = "output",
        .m = "mode",
        .d = "device",
    };
};

fn usage(target: anytype) !void {
    try target.writeAll("not implemented yet");
}

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = &gpa.allocator;

    var cli = try args_parser.parseForCurrentProcess(CliArgs, allocator);
    defer cli.deinit();

    if (cli.positionals.len > 1) {
        try usage(std.io.getStdErr().writer());
        return 1;
    }

    if (cli.options.help) {
        try usage(std.io.getStdOut().writer());
        return 0;
    }

    if (cli.options.device != null and cli.options.@"start-address" != null) {
        var writer = std.io.getStdErr().writer();
        try writer.writeAll("Cannot set --device and --start-address at the same time!\n");
        try usage(writer);
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
        };
    }

    std.debug.assert(cli.options.@"start-address" != null);

    switch (cli.options.mode) {
        .compile => {
            var input_file: std.fs.File = if (cli.positionals.len > 0 and !std.mem.eql(u8, "-", cli.positionals[0]))
                try std.fs.cwd().openFile(cli.positionals[0], .{})
            else
                std.io.getStdIn();
            defer if (cli.positionals.len > 0)
                input_file.close();

            const Line = struct {
                number: u16,
                tokens: []u8,
            };

            var lines = std.ArrayList(Line).init(allocator);
            defer lines.deinit();

            var string_arena = std.heap.ArenaAllocator.init(allocator);
            defer string_arena.deinit();

            {
                var reader = input_file.reader();

                var line_buffer: [1024]u8 = undefined;

                while (true) {
                    const buffer = (try reader.readUntilDelimiterOrEof(&line_buffer, '\n')) orelse break;

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
                        else for (tokens) |tok| {
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
                var output_file: std.fs.File = if (cli.options.output) |out|
                    try std.fs.cwd().createFile(out, .{})
                else
                    std.io.getStdOut();
                defer if (cli.options.output != null)
                    output_file.close();

                var start_offset: u16 = cli.options.@"start-address".?;

                var stream = output_file.writer();
                try stream.writeIntLittle(u16, start_offset);
                for (lines.items) |line| {
                    start_offset += @intCast(u16, 0x05 + 0x01 + line.tokens.len);

                    try stream.writeIntLittle(u16, start_offset);
                    try stream.writeIntLittle(u16, line.number);
                    try stream.writeAll(line.tokens);
                    try stream.writeByte(0);
                }

                // Write "END OF FILE"
                try stream.writeAll(&[_]u8{ 0x00, 0x00, 0x00 });
            }
        },

        .decompile => {
            @panic("not implemented yet!");
        },
    }

    return 0;
}

const Token = struct {
    text: []const u8,
    sequence: []const u8,
};

const tokens = [_]Token{
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
    Token{ .text = "MID", .sequence = "\xca" },
    Token{ .text = "GO", .sequence = "\xcb" },
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
};
