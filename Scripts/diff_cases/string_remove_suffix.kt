fun main() {
    // Basic removeSuffix
    println("hello world".removeSuffix("world"))
    println("hello world".removeSuffix("hello"))
    println("hello".removeSuffix(""))
    println("".removeSuffix("abc"))
    println("".removeSuffix(""))

    // Suffix equals the whole string
    println("abc".removeSuffix("abc"))
    println("a".removeSuffix("a"))

    // Suffix longer than the string
    println("hi".removeSuffix("hello"))

    // Case sensitivity
    println("HelloWorld".removeSuffix("world"))
    println("HelloWorld".removeSuffix("World"))

    // Special characters
    println("foo.bar.kt".removeSuffix(".kt"))
    println("path/to/file".removeSuffix("/file"))
    println("data\n".removeSuffix("\n"))
    println("tab\there".removeSuffix("\there"))

    // Unicode
    println("こんにちは世界".removeSuffix("世界"))
    println("café".removeSuffix("é"))

    // Repeated suffix pattern
    println("aaa".removeSuffix("a"))
    println("abcabc".removeSuffix("abc"))

    // Chain calls
    println("file.tar.gz".removeSuffix(".gz").removeSuffix(".tar"))

    // Result type check – still a String
    val result: String = "test.txt".removeSuffix(".txt")
    println(result)
    println(result.length)
}
