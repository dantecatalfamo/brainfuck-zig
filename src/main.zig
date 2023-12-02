const std = @import("std");
const testing = std.testing;
const allocator = std.heap.page_allocator;

const memory_size = 30_000;
const max_file_size = 1024 * 1024 * 1024;

pub fn main() anyerror!void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    if (args.len != 2 and !(args.len == 3 and std.mem.eql(u8, args[1], "-e"))) {
        try stderr.print("usage: brainfuck [-e expression] [file path]\n", .{});
        std.os.exit(1);
    }

    if (args.len == 3) {
        const program = args[2];
        interpret(program, stdin, stdout, stderr) catch std.os.exit(1);
    } else if (args.len == 2) {
        const file_path = args[1];
        const program = std.fs.cwd().readFileAlloc(allocator, file_path, max_file_size) catch {
            try stderr.print("File not found: {s}\n", .{file_path});
            std.os.exit(1);
        };
        defer allocator.free(program);
        interpret(program, stdin, stdout, stderr) catch std.os.exit(1);
    }
}

pub fn interpret(program: []const u8, reader: anytype, writer: anytype, error_writer: anytype) anyerror!void {
    var memory = [_]i32{0} ** memory_size;
    var index: u32 = 0;
    var program_counter: u32 = 0;

    while (program_counter < program.len) {
        const character = program[program_counter];

        switch (character) {
            '>' => {
                if (index == memory_size - 1) {
                    try error_writer.print("Error: index out of upper bounds at char {d}\n", .{program_counter});
                    return error.IndexOutOfBounds;
                }
                index += 1;
            },
            '<' => {
                if (index == 0) {
                    try error_writer.print("Error: index out of lower bounds at char {d}\n", .{program_counter});
                    return error.IndexOutOfBounds;
                }
                index -= 1;
            },
            '+' => {
                memory[index] +%= 1;
            },
            '-' => {
                memory[index] -%= 1;
            },
            '.' => {
                const out_byte: u8 = @truncate(@as(u32, @bitCast(memory[index])));
                try writer.writeByte(out_byte);
            },
            ',' => {
                memory[index] = reader.readByte() catch 0;
            },
            '[' => {
                if (memory[index] == 0) {
                    const start = program_counter;
                    var depth: u32 = 1;
                    while (program_counter < program.len - 1) {
                        program_counter += 1;
                        const seek_char = program[program_counter];
                        if (seek_char == ']') {
                            depth -= 1;
                        }
                        if (depth == 0) {
                            break;
                        }
                        if (seek_char == '[') {
                            depth += 1;
                        }
                    }
                    if (program_counter == program.len - 1 and depth != 0) {
                        try error_writer.print("Error: missing closing braket to opening bracket at char {d}\n", .{start});
                        return error.MissingClosingBracket;
                    }
                }
            },
            ']' => {
                if (memory[index] != 0) {
                    const start = program_counter;
                    var depth: u32 = 1;
                    while (program_counter > 0) {
                        program_counter -= 1;
                        const seek_char = program[program_counter];
                        if (seek_char == '[') {
                            depth -= 1;
                        }
                        if (depth == 0) {
                            break;
                        }
                        if (seek_char == ']') {
                            depth += 1;
                        }
                    }
                    if (program_counter == 0 and depth != 0) {
                        try error_writer.print("Error: missing opening bracket to closing bracket at char {d}\n", .{start});
                        return error.MissingOpeningBracket;
                    }
                }
            },
            else => {},
        }
        program_counter += 1;
    }
}

test "get cell bit width brainfuck" {
    const program =
        \\ // This generates 65536 to check for larger than 16bit cells
        \\ [-]>[-]++[<++++++++>-]<[>++++++++<-]>[<++++++++>-]<[>++++++++<-]>[<+++++
        \\ +++>-]<[[-]
        \\ [-]>[-]+++++[<++++++++++>-]<+.-.
        \\ [-]]
        \\ // This section is cell doubling for 16bit cells
        \\ >[-]>[-]<<[-]++++++++[>++++++++<-]>[<++++>-]<[->+>+<<]>[<++++++++>-]<[>+
        \\ +++++++<-]>[<++++>-]>[<+>[-]]<<[>[-]<[-]]>[-<+>]<[[-]
        \\ [-]>[-]+++++++[<+++++++>-]<.+++++.
        \\ [-]]
        \\ // This section is cell quadrupling for 8bit cells
        \\ [-]>[-]++++++++[<++++++++>-]<[>++++<-]+>[<->[-]]<[[-]
        \\ [-]>[-]+++++++[<++++++++>-]<.
        \\ [-]]
        \\ [-]>[-]++++[-<++++++++>]<.[->+++<]>++.+++++++.+++++++++++.[----<+>]<+++.
        \\ +[->+++<]>.++.+++++++..+++++++.[-]++++++++++.[-]<
    ;
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    const stdin = std.io.getStdIn().reader();
    const stdout = output.writer();
    const stderr = std.io.null_writer;

    try interpret(program, stdin, stdout, stderr);

    try std.testing.expectEqualStrings("32 bit cells\n", output.items);
}

test "write in cell outside of array bottom" {
    const program = "<<<+";
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.null_writer;
    const stderr = std.io.null_writer;

    const output = interpret(program, stdin, stdout, stderr);
    try testing.expectError(error.IndexOutOfBounds, output);
}

test "write in cell outside of array top" {
    const program = ">" ** memory_size;
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.null_writer;
    const stderr = std.io.null_writer;

    const output = interpret(program, stdin, stdout, stderr);
    try testing.expectError(error.IndexOutOfBounds, output);
}

test "write number over 255 to writer" {
    const program = "+" ** 300 ++ ".";
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.null_writer;
    const stderr = std.io.null_writer;

    try interpret(program, stdin, stdout, stderr);
}

test "write negative number to writer" {
    const program = "-" ** 200 ++ ".";
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.null_writer;
    const stderr = std.io.null_writer;

    try interpret(program, stdin, stdout, stderr);
}

test "loop without end" {
    const program = "[><";
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.null_writer;
    const stderr = std.io.null_writer;

    const output = interpret(program, stdin, stdout, stderr);
    try testing.expectError(error.MissingClosingBracket, output);
}

test "loop without beginning" {
    const program = "+><]";
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.null_writer;
    const stderr = std.io.null_writer;

    const output = interpret(program, stdin, stdout, stderr);
    try testing.expectError(error.MissingOpeningBracket, output);
}
