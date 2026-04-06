fun main() {
    println("true".toBooleanStrictOrNull())   // true
    println("false".toBooleanStrictOrNull())  // false
    println("yes".toBooleanStrictOrNull())    // null
    println("True".toBooleanStrictOrNull())   // null (strict = case-sensitive)

    println("127".toByte())    // 127
    println("-128".toByte())   // -128
    println("200".toByteOrNull())  // null (out of range)

    println("32767".toShort())  // 32767
    println("abc".toShortOrNull())  // null
}
