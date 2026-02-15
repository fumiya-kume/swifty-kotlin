fun pickInt(v: Int) = v + 1
fun pickBool(v: Boolean) = if (v) 1 else 0

fun main() {
    println(pickInt(41))
    println(pickBool(true))
}
