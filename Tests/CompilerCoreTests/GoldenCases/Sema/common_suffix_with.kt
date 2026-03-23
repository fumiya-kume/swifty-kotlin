fun main() {
    println("abcdef".commonSuffixWith("xyzdef"))
    println("abcDEF".commonSuffixWith("xyzdef", true))
    println("abcDEF".commonSuffixWith("xyzdef", false))
    println("abcdef".commonPrefixWith("abcxyz"))
    println("ABCdef".commonPrefixWith("abcxyz", true))
}
