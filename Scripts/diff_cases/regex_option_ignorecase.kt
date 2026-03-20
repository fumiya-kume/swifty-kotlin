fun main() {
    // STDLIB-598: RegexOption.IGNORE_CASE basic matching
    val regex = Regex("[a-z]+", RegexOption.IGNORE_CASE)
    println(regex.containsMatchIn("HELLO"))
    println(regex.containsMatchIn("123"))

    // STDLIB-598: find with IGNORE_CASE
    val found = regex.find("ABC123")
    println(found?.value)

    // STDLIB-598: matchEntire with IGNORE_CASE
    val match = Regex("[a-z]+", RegexOption.IGNORE_CASE).matchEntire("Hello")
    println(match?.value)
    val noMatch = Regex("[a-z]+", RegexOption.IGNORE_CASE).matchEntire("Hello123")
    println(noMatch?.value)

    // STDLIB-598: findAll with IGNORE_CASE
    val results = Regex("[a-z]+", RegexOption.IGNORE_CASE).findAll("ABC 123 DEF")
    println(results.map { it.value }.toList())

    // STDLIB-598: pattern property preserved
    val r = Regex("[A-Z]+", RegexOption.IGNORE_CASE)
    println(r.pattern)

    // STDLIB-598: case-insensitive matches on String
    println("HELLO".matches(Regex("[a-z]+", RegexOption.IGNORE_CASE)))
    println("hello".matches(Regex("[A-Z]+", RegexOption.IGNORE_CASE)))
    println("Hello123".matches(Regex("[a-z]+", RegexOption.IGNORE_CASE)))

    // STDLIB-598: replace with IGNORE_CASE
    println("Hello World".replace(Regex("[a-z]+", RegexOption.IGNORE_CASE), "X"))

    // STDLIB-598: split with IGNORE_CASE
    println("oneABCtwo DEF three".split(Regex("[a-z]+", RegexOption.IGNORE_CASE)))
}
