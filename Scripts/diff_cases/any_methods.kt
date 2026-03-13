fun checkBoolAny(value: Any) {
    println(value.hashCode())
    println(value.toString())
    println(value.equals(true))
    println(value.equals(false))
}

fun main() {
    println(42.hashCode())
    println(42.toString())
    println(42.equals(42))
    println(42.equals(43))
    val s: Any = "x"
    println(s.toString())
    println(s.equals("x"))
    println(s.equals("y"))
    checkBoolAny(true)
    val n: Any? = null
    println(n?.toString())
}
