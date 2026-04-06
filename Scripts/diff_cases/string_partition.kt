fun main() {
    val (letters, others) = "hello world!".partition { it.isLetter() }
    println(letters)  // helloworld
    println(others)   // " !"

    val (upper, lower) = "Hello World".partition { it.isUpperCase() }
    println(upper)    // HW
    println(lower)    // ello orld
}
