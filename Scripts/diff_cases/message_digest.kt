// SKIP-DIFF
import java.security.getInstance
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

private fun hex(bytes: ByteArray): String =
    bytes.joinToString("") { ((it + 256) % 256).toString(16).padStart(2, '0') }

fun main() {
    val input = byteArrayOf(97, 98, 99)

    println(hex(getInstance("MD5").digest(input)))
    println(hex(getInstance("SHA-1").digest(input)))
    println(hex(getInstance("SHA-256").digest(input)))
    println(hex(getInstance("SHA-512").digest(input)))

    val macAlgorithms = listOf("HmacMD5", "HmacSHA1", "HmacSHA256", "HmacSHA512")
    for (algorithm in macAlgorithms) {
        val key = SecretKeySpec(byteArrayOf(107, 101, 121), algorithm)
        val mac = Mac.getInstance(algorithm)
        mac.init(key)
        println(hex(mac.doFinal(input)))
    }
}
