fun main() {
    // STDLIB-597: Regex.containsMatchIn
    val regex = Regex("[a-z]+")
    println(regex.containsMatchIn("hello123"))
    println(regex.containsMatchIn("123"))

    // STDLIB-598: String.matches(Regex)
    println("hello".matches(Regex("[a-z]+")))
    println("hello123".matches(Regex("[a-z]+")))

    // STDLIB-599: Regex.find, replace, split
    val found = Regex("[0-9]+").find("abc123def")
    println(found?.value)
    println("abc123def456".replace(Regex("[0-9]+"), "X"))
    println("one1two2three".split(Regex("[0-9]+")))
    val r = "[a-z]+".toRegex()
    println(r.pattern)
}
