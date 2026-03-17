package golden.sema

import kotlin.io.Closeable

class MyResource : Closeable {
    override fun close() {
        println("closed")
    }
}

fun useBasic(): Unit {
    val r = MyResource()
    r.use { println("using") }
}

fun useReturnValue(): Int {
    val r = MyResource()
    return r.use { 42 }
}

fun useWithIt(): String {
    val r = MyResource()
    return r.use { it.toString() }
}
