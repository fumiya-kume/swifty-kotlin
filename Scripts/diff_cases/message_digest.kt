// SKIP-DIFF: kswiftc exposes MessageDigest through a synthetic java.security.getInstance top-level stub; JVM kotlinc requires MessageDigest.getInstance.
import java.security.getInstance

private fun hex(bytes: ByteArray): String {
    val sb = StringBuilder()
    for (i in 0..bytes.size - 1) {
        val b = bytes[i]
        val v = ((b.toInt()) + 256) % 256
        val s = v.toString(16).padStart(2, '0')
        sb.append(s)
    }
    return sb.toString()
}

fun main() {
    val input = byteArrayOf(97, 98, 99)

    val md5 = getInstance("MD5")
    println("MD5: ${hex(md5.digest(input))}")

    val sha1 = getInstance("SHA-1")
    println("SHA-1: ${hex(sha1.digest(input))}")

    val sha256 = getInstance("SHA-256")
    println("SHA-256: ${hex(sha256.digest(input))}")
}
