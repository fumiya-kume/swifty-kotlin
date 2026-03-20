import java.io.File

fun main() {
    val base = "/tmp/kswiftk_listfiles_" + System.currentTimeMillis()
    val dir = File(base)
    try {
        dir.mkdirs()
        File(base + "/alpha.txt").writeText("a")
        File(base + "/beta.txt").writeText("b")
        File(base + "/sub").mkdirs()

        // listFiles returns files in directory (nullable)
        val files = dir.listFiles()
        if (files != null) {
            val sorted = files.sortedBy { it.name }
            for (f in sorted) {
                println(f.name)
            }
        }

        // listFiles on non-directory returns null
        val nonDir = File(base + "/alpha.txt")
        val result = nonDir.listFiles()
        println(result == null)
    } finally {
        File(base + "/alpha.txt").delete()
        File(base + "/beta.txt").delete()
        File(base + "/sub").delete()
        dir.delete()
    }
}
