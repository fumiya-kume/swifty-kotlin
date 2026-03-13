package golden.sema

fun main() {
    val obj = object {
        val x = 42
        val y: String = "hello"
    }
    println(obj.x)
    println(obj.y)
}
