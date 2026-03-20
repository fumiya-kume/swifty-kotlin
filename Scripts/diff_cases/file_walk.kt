import java.io.File

fun main() {
    val base = "/tmp/kswiftk_walk_test"
    val dir = File(base)
    try {
        // Clean up from previous run
        File(base + "/a/b/deep.txt").delete()
        File(base + "/a/hello.txt").delete()
        File(base + "/root.txt").delete()
        File(base + "/a/b").delete()
        File(base + "/a").delete()
        dir.delete()

        // Set up directory structure
        File(base + "/a/b").mkdirs()
        File(base + "/a/b/deep.txt").writeText("deep")
        File(base + "/a/hello.txt").writeText("hello")
        File(base + "/root.txt").writeText("root")

        // walk() returns all files recursively including root
        val walked = dir.walk().sortedBy { it.path }
        for (f in walked) {
            println(f.name)
        }
    } finally {
        // cleanup
        File(base + "/a/b/deep.txt").delete()
        File(base + "/a/hello.txt").delete()
        File(base + "/root.txt").delete()
        File(base + "/a/b").delete()
        File(base + "/a").delete()
        dir.delete()
    }
}
