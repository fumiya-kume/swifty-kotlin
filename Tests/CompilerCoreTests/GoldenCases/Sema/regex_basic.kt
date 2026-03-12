fun main() {
    val regex = Regex("[a-z]+")
    println("hello".matches(regex))
    println("hello".contains(regex))
    val found = regex.find("abc123")
    println(found?.value)
    println("abc123".replace(Regex("[0-9]+"), "X"))
    println("a1b2".split(Regex("[0-9]+")))
    val r = "test".toRegex()
    println(r.pattern)
}
