fun main() {
    // Basic regex operations
    val text = "hello world"

    // find
    val regex = Regex("[a-z]+")
    val found = regex.find(text)
    println("find: ${found?.value}")

    // findAll
    val allMatches = regex.findAll(text).toList()
    println("findAll count: ${allMatches.size}")
    println("findAll: ${allMatches.map { it.value }}")

    // containsMatchIn
    println("contains: ${regex.containsMatchIn(text)}")
    println("contains: ${Regex("[0-9]+").containsMatchIn(text)}")

    // matchEntire
    println("matchEntire: ${Regex("[a-z]+").matchEntire("hello")?.value}")
    println("matchEntire: ${Regex("[a-z]+").matchEntire("hello123")}")

    // replace
    println("replace: ${text.replace(Regex("[aeiou]"), "*")}")

    // pattern property
    println("pattern: ${regex.pattern}")
}
