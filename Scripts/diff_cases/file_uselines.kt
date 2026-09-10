import java.io.File

fun main() {
    val f = File("/tmp/kswiftk_uselines_" + System.currentTimeMillis() + ".txt")
    try {
        f.writeText("one\ntwo\nthree")
        val result = f.useLines { lines ->
            lines.count()
        }
        println("count: $result")

        // useLines returning a List consumed outside the block.
        // NOTE: member access on the useLines result (collected.size /
        // .first()) is unresolved under the kklib stdlib path — see BUG-238.
        val collected = f.useLines { lines ->
            lines.toList()
        }
        println("collected: $collected")
    } finally {
        f.delete()
    }
}
