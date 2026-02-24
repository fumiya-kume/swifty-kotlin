open class Box<T>(val value: T) {
    fun get(): T = value
    fun set(v: T) {}
}

fun readStar(box: Box<*>): Any? = box.get()

fun main() {
    val box = Box(42)
    println(readStar(box))
}
