fun main() {
    val x: UInt = 42u
    val y: ULong = 42uL
    val a = x.toInt()
    val b = x.toUInt()
    val c = x.toLong()
    val d = x.toULong()
    val e = y.toInt()
    val f = 100u / 3u
    val g = 100u % 3u
    val i = 255u and 15u
    val j = 240u or 15u
    val k = 255u xor 15u
    println(a)
    println(b)
    println(c)
    println(d)
    println(e)
    println(f)
    println(g)
    println(i)
    println(j)
    println(k)
}
