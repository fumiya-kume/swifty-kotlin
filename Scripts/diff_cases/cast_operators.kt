fun main() {
    val v: Any = "hello"
    println(v as String)
    println(v as? String)
    println(v as? Int)
}
