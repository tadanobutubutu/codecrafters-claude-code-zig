const std = @import("std");

pub fn main() !void {
    // コンパイルエラーを起こして std.json.Stringify.value の型を表示させる
    const T = @TypeOf(std.json.Stringify.value);
    @compileError(@typeName(T));
}
