fun main() {
    val s = "Hello, World!"
    println(s.filter { it.isUpperCase() })
    println(s.map { it.uppercase() })
    println(s.count { it == 'l' })
    println(s.any { it.isDigit() })
    println(s.all { it.isLetter() })
    println(s.none { it.isDigit() })
    println("abc".reversed())
    println("hello".padStart(10))
    println("hello".padStart(10, '*'))
    println("hello".padEnd(10, '-'))
    println("Hello".equals("hello", ignoreCase = true))
    println("Hello".equals("hello", ignoreCase = false))
}
