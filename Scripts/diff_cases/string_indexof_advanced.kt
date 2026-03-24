fun main() {
    val s = "hello world hello"
    println(s.indexOf("hello"))
    println(s.lastIndexOf("hello"))
    println(s.indexOf("hello", 1))
    println(s.indexOf("xyz"))
    println(s.indexOfFirst { it == 'o' })
    println(s.indexOfLast { it == 'o' })
    println(s.indexOfFirst { it == 'z' })
}
