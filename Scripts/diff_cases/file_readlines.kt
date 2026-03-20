import java.io.File

fun main() {
    val f = File("/tmp/kswiftk_readlines_" + System.currentTimeMillis() + ".txt")
    try {
        f.writeText("alpha\nbeta\ngamma")
        val lines = f.readLines()
        println(lines.size)
        for (line in lines) {
            println(line)
        }

        // empty file
        f.writeText("")
        println(f.readLines().size)

        // trailing newline
        f.writeText("one\ntwo\n")
        val lines2 = f.readLines()
        println(lines2.size)
        for (l in lines2) {
            println(l)
        }
    } finally {
        f.delete()
    }
}
