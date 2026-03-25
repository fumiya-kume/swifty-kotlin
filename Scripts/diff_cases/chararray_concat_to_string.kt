fun main() {
    // Basic concatToString
    val chars = charArrayOf('H', 'e', 'l', 'l', 'o')
    println(chars.concatToString())

    // Empty CharArray
    val empty = charArrayOf()
    println(empty.concatToString())
    println(empty.concatToString().isEmpty())

    // Single character
    val single = charArrayOf('A')
    println(single.concatToString())

    // Round-trip: String -> CharArray -> String
    val original = "Kotlin"
    val roundTripped = original.toCharArray().concatToString()
    println(roundTripped)

    // Special characters
    val special = charArrayOf('\n', '\t', '\\', '\'')
    println(special.concatToString().length)

    // Digits
    val digits = charArrayOf('0', '1', '2', '3', '4', '5', '6', '7', '8', '9')
    println(digits.concatToString())

    // Unicode characters
    val unicode = charArrayOf('\u0048', '\u0065', '\u006C', '\u006C', '\u006F')
    println(unicode.concatToString())

    // concatToString result used in string operations
    val greeting = charArrayOf('H', 'i')
    println(greeting.concatToString() + " there")
    println(greeting.concatToString().length)
}
// SKIP-DIFF: CharArray concatToString parity pending
