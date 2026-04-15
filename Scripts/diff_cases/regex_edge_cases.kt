fun main() {
    val regex = Regex("[a-z]+")
    println(regex.containsMatchIn("123abc"))
    println(regex.matchEntire("abc")?.value)
    println(regex.matchEntire("abc123"))

    println("a b   c".replace(Regex("\\s+"), "-"))
    println("one1two2three".split(Regex("[0-9]+")))
}
