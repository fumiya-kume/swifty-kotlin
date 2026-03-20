fun main() {
    // Basic commonSuffixWith (1-arg)
    println("abcdef".commonSuffixWith("xyzdef"))
    println("hello".commonSuffixWith("world"))
    println("kotlin".commonSuffixWith("kotlin"))
    println("abc".commonSuffixWith(""))
    println("".commonSuffixWith("abc"))

    // commonSuffixWith with ignoreCase (2-arg)
    println("abcDEF".commonSuffixWith("xyzdef", true))
    println("abcDEF".commonSuffixWith("xyzdef", false))
    println("HELLO".commonSuffixWith("hello", true))
    println("HELLO".commonSuffixWith("hello", false))

    // Basic commonPrefixWith (1-arg)
    println("abcdef".commonPrefixWith("abcxyz"))
    println("hello".commonPrefixWith("world"))

    // commonPrefixWith with ignoreCase (2-arg)
    println("ABCdef".commonPrefixWith("abcxyz", true))
    println("ABCdef".commonPrefixWith("abcxyz", false))
}
