fun main() {
    val a = "HelloWorld"
    val b = "HelloKotlin"
    println(a.commonPrefixWith(b))
    println("abc".commonPrefixWith("xyz"))
    println("".commonPrefixWith("abc"))
    println("HelloWorld".commonPrefixWith("HelloKotlin", false))
    println("HelloWorld".commonPrefixWith("helloKotlin", true))
    println("ABCdef".commonPrefixWith("abcXYZ", true))
    println("XYZ".commonPrefixWith("abc", true))
    println("Hello".commonPrefixWith("hello", false))
    println("HelloWorld".commonSuffixWith("MyWorld"))
    println("HelloWORLD".commonSuffixWith("MyWorld", true))
    println("HelloWORLD".commonSuffixWith("MyWorld", false))
}
