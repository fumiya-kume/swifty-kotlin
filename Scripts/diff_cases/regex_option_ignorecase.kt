fun main() {
    // Basic regex operations
    val regex = Regex("[a-z]+")
    println(regex.containsMatchIn("hello"))
    println(regex.containsMatchIn("123"))

    // find
    val found = regex.find("abc123")
    println(found?.value)

    // pattern property
    println(regex.pattern)

    // String.matches
    println("hello".matches(Regex("[a-z]+")))
    println("hello123".matches(Regex("[a-z]+")))

    // replace
    println("hello world".replace(Regex("[aeiou]"), "*"))

    // split
    println("one two three".split(Regex("\\s+")))
}
