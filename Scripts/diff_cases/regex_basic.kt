fun main() {
    // STDLIB-100: Regex constructor, matches, contains
    val regex = Regex("[a-z]+[0-9]+")
    println("abc123".matches(regex))
    println("ABC".matches(regex))
    println("abc123".contains(Regex("[0-9]+")))

    // STDLIB-101: find
    val found = Regex("[0-9]+").find("abc123def456")
    println(found?.value)

    // STDLIB-102: replace, split with Regex
    println("abc123def".replace(Regex("[0-9]+"), "X"))
    println("one1two2three".split(Regex("[0-9]+")))

    // STDLIB-103: toRegex, pattern
    val r = "[a-z]+".toRegex()
    println(r.pattern)
}
