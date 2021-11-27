const std = @import("std");
const allocator = std.heap.page_allocator;

const memory_size = 30_000;

pub fn main() anyerror!void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const stderr = std.io.getStdErr().writer();

    if (args.len != 2) {
        try stderr.print("usage: brainfuck <file path>\n", .{});
        std.os.exit(1);
    }
    const file_path = args[1];

    const program = try std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024 * 1024);
    defer allocator.free(program);

    try interpret(program);
}

pub fn interpret(program: []const u8) anyerror!void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    var memory = [_]i32{0} ** memory_size;
    var index: u32 = 0;
    var program_counter: u32 = 0;

    while (program_counter < program.len) {
        var character = program[program_counter];

        switch(character) {
            '>' => {
                if (index == memory_size - 1) { return error.IndexOutOfBounds; }
                index += 1;
            },
            '<' => {
                if (index == 0) { return error.IndexOutOfBounds; }
                index -=1 ;
            },
            '+' => {
                memory[index] += 1;
            },
            '-' => {
                memory[index] -= 1;
            },
            '.' => {
                const out_byte = @truncate(u8, @intCast(u32, memory[index]));
                try stdout.writeByte(out_byte);
            },
            ',' => {
                memory[index] = stdin.readByte() catch 0;
            },
            '[' => {
                if (memory[index] == 0) {
                    var depth: u32 = 1;
                    while (program_counter < program.len) {
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
                }
            },
            ']' => {
                if (memory[index] != 0) {
                    var depth: u32 = 1;
                    while (program_counter >= 0) {
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
                }
            },
            else => { }
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
    std.debug.print("\n", .{});
    try interpret(program);
}

test "write in cell outside of array bottom" {
    const program = "<<<+";
    const output = interpret(program);
    try std.testing.expectError(error.IndexOutOfBounds, output);
}

test "write in cell outside of array top" {
    const program = ">" ** memory_size;
    const output = interpret(program);
    try std.testing.expectError(error.IndexOutOfBounds, output);
}
