import java.security.SecureRandom

fun main() {
    // getInstance() returns a SecureRandom instance
    val sr = SecureRandom.getInstance()

    // nextBytes() fills a ByteArray with cryptographically secure random bytes
    val buf = ByteArray(8)
    sr.nextBytes(buf)
    println("nextBytes size: ${buf.size}")

    // generateSeed() returns a ByteArray of the requested length
    val seed = sr.generateSeed(4)
    println("generateSeed size: ${seed.size}")

    // setSeed() influences subsequent output when a seed is provided
    val sr2 = SecureRandom.getInstance()
    sr2.setSeed(42)
    val buf2a = ByteArray(4)
    sr2.nextBytes(buf2a)

    val sr3 = SecureRandom.getInstance()
    sr3.setSeed(42)
    val buf2b = ByteArray(4)
    sr3.nextBytes(buf2b)

    // Two instances with the same seed produce identical byte sequences
    println("seeded sequences match: ${buf2a.toList() == buf2b.toList()}")

    println("OK")
}
