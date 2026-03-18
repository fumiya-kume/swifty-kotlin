fun main() {
    val s = buildString {
        appendRange("Hello, World!", 0, 5)
        append(" ")
        appendRange("Hello, World!", 7, 13)
    }
    println(s)

    // UTF-16 indexing: CJK characters are single UTF-16 code units (BMP),
    // but multi-byte in UTF-8 -- verifies correct index model.
    val u = buildString {
        appendRange("ABCDE", 1, 4)
        append("|")
        appendRange("abcdef", 0, 3)
        append("|")
        appendRange("12345", 2, 5)
    }
    println(u)
}
