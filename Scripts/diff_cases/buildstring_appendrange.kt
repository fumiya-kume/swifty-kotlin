fun main() {
    val s = buildString {
        appendRange("Hello, World!", 0, 5)
        append(" ")
        appendRange("Hello, World!", 7, 13)
    }
    println(s)

    // ASCII range slicing: basic start/end validation.
    val u = buildString {
        appendRange("ABCDE", 1, 4)
        append("|")
        appendRange("abcdef", 0, 3)
        append("|")
        appendRange("12345", 2, 5)
    }
    println(u)

    // CJK characters are single UTF-16 code units (BMP) but multi-byte in
    // UTF-8.  Slicing by UTF-16 index should differ from a naive byte index.
    val cjk = buildString {
        appendRange("\u4F60\u597D\u4E16\u754C", 1, 3)  // "好世" from "你好世界"
    }
    println(cjk)
}
