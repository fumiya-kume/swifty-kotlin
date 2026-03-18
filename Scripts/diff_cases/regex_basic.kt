fun main() {
    // STDLIB-620: Regex constructor, containsMatchIn
    val regex = Regex("[0-9]+")
    println(regex.containsMatchIn("abc123"))

    // STDLIB-620: Regex.find
    println(regex.find("abc123def456")?.value)

    // STDLIB-620: String.matches
    println("abc123".matches(Regex("[a-z]+[0-9]+")))
    println("ABC".matches(Regex("[a-z]+[0-9]+")))
    println("abc".matches(Regex("[a-z]+")))
    println("ABC".matches(Regex("[a-z]+")))

    // STDLIB-620: String.contains(Regex)
    println("abc123".contains(Regex("[0-9]+")))

    // STDLIB-620: String.replace with Regex
    println("hello world".replace(Regex("\\s+"), "_"))
    println("abc123def".replace(Regex("[0-9]+"), "X"))

    // STDLIB-620: String.split with Regex
    println("one1two2three".split(Regex("[0-9]+")))

    // STDLIB-620: toRegex, pattern
    val r = "[a-z]+".toRegex()
    println(r.pattern)
}
