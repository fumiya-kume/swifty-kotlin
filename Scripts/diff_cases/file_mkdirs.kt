import java.io.File

fun main() {
    val base = "/tmp/kswiftk_mkdirs_" + System.currentTimeMillis()
    val baseDir = File(base)
    val nested = File(base + "/a/b/c")
    val file = File(base + "/a/b/c/hello.txt")
    try {
        // mkdirs creates intermediate directories
        println(nested.mkdirs())   // true
        println(nested.exists())   // true
        println(nested.isDirectory) // true

        // second call returns false (already exists)
        println(nested.mkdirs())   // false

        // create a file inside
        file.writeText("content")
        println(file.exists())    // true

        // delete file
        println(file.delete())    // true
        println(file.exists())    // false

        // delete empty leaf directory
        println(nested.delete())  // true
        println(nested.exists())  // false
    } finally {
        // cleanup remaining dirs (leaf-to-root order)
        File(base + "/a/b/c").delete()
        File(base + "/a/b").delete()
        File(base + "/a").delete()
        baseDir.delete()
    }
}
