fun main() {
    val i: Int = 42
    val l: Long = i.toLong()
    val d: Double = i.toDouble()
    val f: Float = i.toFloat()
    println(l)
    println(d)
    println(f)

    val l2: Long = 123456789012345L
    println(l2.toInt())
    println(l2.toDouble())
    println(l2.toFloat())

    val d2: Double = 3.14159
    println(d2.toInt())
    println(d2.toLong())
    println(d2.toFloat())
}
