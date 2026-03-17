fun main() {
    val regex = Regex("[0-9]+")
    println(regex.containsMatchIn("abc123"))
    println(regex.find("abc123def456")?.value)
    println(regex.findAll("abc123def456").map { it.value }.toList())
    println("hello world".replace(Regex("\\s+"), "_"))
    println("abc".matches(Regex("[a-z]+")))
    println("ABC".matches(Regex("[a-z]+")))
}
