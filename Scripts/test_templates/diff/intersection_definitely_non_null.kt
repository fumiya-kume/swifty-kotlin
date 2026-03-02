fun Any.idTag(): Int = 7

fun <T : Any?> directValue(x: T & Any): Int = x.idTag()
fun <T : Any?> safeValue(x: T & Any): Int? = x?.idTag()

fun main() {
    println(directValue("hello"))
    println(safeValue("world"))
}
