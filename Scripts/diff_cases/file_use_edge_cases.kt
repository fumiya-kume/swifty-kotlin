// SKIP-DIFF
import java.io.Closeable
import java.io.File

class TraceResource(private val name: String) : Closeable {
    override fun close() {
        println("close:$name")
    }
}

fun main() {
    val result = TraceResource("ok").use {
        println("use:ok")
        "done"
    }
    println(result)

    try {
        TraceResource("fail").use {
            println("use:fail")
            error("boom")
        }
    } catch (e: Throwable) {
        println("caught")
    }

    val nullable: TraceResource? = null
    println(nullable?.use { "nope" })

    val file = File("/tmp/kswiftk_file_use_edge_cases.txt")
    file.delete()
    println(file.exists())
    println(file.createNewFile())
    println(file.exists())
    println(file.delete())
    println(file.exists())
}
