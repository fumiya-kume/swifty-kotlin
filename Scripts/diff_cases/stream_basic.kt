import java.io.File
import java.io.SequenceInputStream

fun main() {
    val tmpFile = File("/tmp/kswiftk_stream_" + System.currentTimeMillis() + ".bin")
    val tmpOut = File("/tmp/kswiftk_stream_out_" + System.currentTimeMillis() + ".bin")
    try {
        // Write bytes via OutputStream
        val os = tmpFile.outputStream()
        os.write(72)  // 'H'
        os.write(101) // 'e'
        os.write(108) // 'l'
        os.write(108) // 'l'
        os.write(111) // 'o'
        os.flush()
        os.close()

        // Read bytes via InputStream
        val ins = tmpFile.inputStream()
        println("available: " + ins.available())
        val b0 = ins.read()
        println("first byte: $b0")

        // mark / reset
        ins.mark(100)
        val b1 = ins.read()
        println("second byte: $b1")
        ins.reset()
        val b1again = ins.read()
        println("after reset: $b1again")

        // skip
        val skipped = ins.skip(2)
        println("skipped: $skipped")
        val b4 = ins.read()
        println("byte after skip: $b4")

        // EOF
        val eof = ins.read()
        println("eof: $eof")
        ins.close()

        // SequenceInputStream chains two streams
        val f2 = File("/tmp/kswiftk_stream2_" + System.currentTimeMillis() + ".bin")
        try {
            f2.writeText("!")
            val s1 = tmpFile.inputStream()
            val s2 = f2.inputStream()
            val seq = SequenceInputStream(s1, s2)
            println("seq available: " + seq.available())
            val c0 = seq.read()
            println("seq first: $c0")
            seq.close()
        } finally {
            f2.delete()
        }
    } finally {
        tmpFile.delete()
        tmpOut.delete()
    }
}
