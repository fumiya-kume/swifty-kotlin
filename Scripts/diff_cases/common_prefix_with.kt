fun main() {
    // Basic commonPrefixWith
    val a = "HelloWorld"
    val b = "HelloKotlin"
    println(a.commonPrefixWith(b))

    // Empty prefix
    println("abc".commonPrefixWith("xyz"))

    // Identical strings
    println("same".commonPrefixWith("same"))

    // Empty string
    println("".commonPrefixWith("abc"))
    println("abc".commonPrefixWith(""))

    // commonPrefixWith with ignoreCase = false
    println("HelloWorld".commonPrefixWith("HelloKotlin", false))

    // commonPrefixWith with ignoreCase = true
    println("HelloWorld".commonPrefixWith("helloKotlin", true))
    println("ABCdef".commonPrefixWith("abcXYZ", true))
    println("ABC".commonPrefixWith("abc", true))

    // ignoreCase = true but no common prefix
    println("XYZ".commonPrefixWith("abc", true))

    // ignoreCase = false with case mismatch
    println("Hello".commonPrefixWith("hello", false))

    // commonSuffixWith basic
    println("HelloWorld".commonSuffixWith("MyWorld"))

    // commonSuffixWith with ignoreCase = true
    println("HelloWORLD".commonSuffixWith("MyWorld", true))

    // commonSuffixWith with ignoreCase = false
    println("HelloWORLD".commonSuffixWith("MyWorld", false))
}
