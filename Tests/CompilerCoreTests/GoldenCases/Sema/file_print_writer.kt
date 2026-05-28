import java.io.File
import java.io.PrintWriter

fun main() {
    val f = File("output.txt")
    val pw = f.printWriter()
    pw.print("hello")
    pw.println(" world")
    pw.println()
    pw.flush()
    pw.close()
}
