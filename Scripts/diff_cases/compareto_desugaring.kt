fun main() {
    val a = "apple"
    val b = "banana"
    println(if (a < b) 1 else 0)
    println(if (a <= b) 1 else 0)
    println(if (a > b) 1 else 0)
    println(if (a >= b) 1 else 0)
    println(if (b < a) 1 else 0)
    println(if (b >= a) 1 else 0)
    println(if (a < a) 1 else 0)
    println(if (a <= a) 1 else 0)
    println(if (a >= a) 1 else 0)
    println(if (a > a) 1 else 0)
}
