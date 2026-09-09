package golden.sema

fun appendValues(builder: StringBuilder, value: Any?, byte: Byte, short: Short, chars: CharArray): StringBuilder {
    builder.append(value)
    builder.append(byte)
    builder.append(short)
    builder.append(chars, 0, 1)
    return builder.appendRange(chars, 0, 1)
}

fun appendLines(builder: StringBuilder, bool: Boolean, byte: Byte, char: Char, chars: CharArray,
                sequence: CharSequence?, double: Double, float: Float, int: Int, long: Long,
                short: Short, string: String?): StringBuilder {
    builder.appendLine(bool)
    builder.appendLine(byte)
    builder.appendLine(char)
    builder.appendLine(chars)
    builder.appendLine(sequence)
    builder.appendLine(double)
    builder.appendLine(float)
    builder.appendLine(int)
    builder.appendLine(long)
    builder.appendLine(short)
    return builder.appendLine(string)
}
