import kotlin.io.Closeable

class MyResource : Closeable {
    override fun close() {
        println("closed")
    }
}

fun main() {
    val r = MyResource()
    r.use {
        println("using resource")
    }
    println("done")
}
