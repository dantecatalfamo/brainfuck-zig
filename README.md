# Brainfuck-zig

Embeddable zig brainfuck interpreter.

## Usage

`usage: brainfuck [-e expression] [file path]`

## Embedding

```zig
const interpreter = @import("brainfuck-zig/src/main.zig").interpreter;

try interpret(program_string, reader, writer, error_writer);
```
