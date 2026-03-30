import java.io.File

fun main() {
    val f = File("/tmp/kswiftk_file_basic_test.txt")

    // createNewFile() should create a new file and return true
    f.delete()
    println(f.createNewFile()) // true
    println(f.exists())        // true
    println(f.isFile)          // true
    println(f.isDirectory)     // false

    // length() of empty file is 0
    println(f.length())        // 0

    // canRead / canWrite should be true for a freshly created file
    println(f.canRead())       // true
    println(f.canWrite())      // true

    // absolutePath and canonicalPath should be non-empty
    println(f.absolutePath.isNotEmpty())   // true
    println(f.canonicalPath.isNotEmpty())  // true

    // parent should be non-null
    println(f.parent != null)  // true

    // lastModified() should be > 0 for an existing file
    println(f.lastModified() > 0) // true

    // File(parent, child) constructor
    val f2 = File("/tmp", "kswiftk_file_basic_test2.txt")
    println(f2.name) // kswiftk_file_basic_test2.txt

    // clean up
    f.delete()
    println("done")
}
