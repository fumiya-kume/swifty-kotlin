fun <T> isOf(v: Any): Boolean = v is T

fun main() {
    println(isOf<Int>(1))
}
