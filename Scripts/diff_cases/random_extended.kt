import kotlin.random.Random

fun main() {
    // STDLIB-514: nextLong() unbounded
    val a = Random.nextLong()
    println("nextLong called: true")

    // STDLIB-515: nextFloat() in [0.0, 1.0)
    var okFloat = true
    repeat(100) {
        val f = Random.nextFloat()
        if (f < 0.0f || f >= 1.0f) {
            okFloat = false
        }
    }
    println("nextFloat in range: $okFloat")

    // STDLIB-655: nextFloat(until)
    var okFloatUntil = true
    repeat(100) {
        val f = Random.nextFloat(5.0f)
        if (f < 0.0f || f >= 5.0f) {
            okFloatUntil = false
        }
    }
    println("nextFloat(5.0f) in range: $okFloatUntil")

    // STDLIB-655: nextFloat(from, until)
    var okFloatRange = true
    repeat(100) {
        val f = Random.nextFloat(1.0f, 10.0f)
        if (f < 1.0f || f >= 10.0f) {
            okFloatRange = false
        }
    }
    println("nextFloat(1.0f, 10.0f) in range: $okFloatRange")

    // STDLIB-654: nextDouble(until)
    var okDoubleUntil = true
    repeat(100) {
        val d = Random.nextDouble(5.0)
        if (d < 0.0 || d >= 5.0) {
            okDoubleUntil = false
        }
    }
    println("nextDouble(5.0) in range: $okDoubleUntil")

    // STDLIB-516: Seeded Random determinism
    val r1 = Random(42)
    val r2 = Random(42)
    println("seeded nextInt match: ${r1.nextInt(100) == r2.nextInt(100)}")
    println("seeded nextLong match: ${r1.nextLong() == r2.nextLong()}")
    println("seeded nextFloat match: ${r1.nextFloat() == r2.nextFloat()}")
    println("seeded nextDouble match: ${r1.nextDouble() == r2.nextDouble()}")
    println("seeded nextBoolean match: ${r1.nextBoolean() == r2.nextBoolean()}")

    // STDLIB-653: nextBytes fills a ByteArray with random bytes
    val r3 = Random(99)
    val r4 = Random(99)
    val bytes1 = r3.nextBytes(ByteArray(8))
    val bytes2 = r4.nextBytes(ByteArray(8))
    println("nextBytes size: ${bytes1.size}")
    println("nextBytes deterministic: ${bytes1.toList() == bytes2.toList()}")

    // Verify byte values are in Byte range [-128, 127]
    var bytesInRange = true
    val r5 = Random(123)
    val bigBytes = r5.nextBytes(ByteArray(200))
    for (b in bigBytes) {
        if (b < -128 || b > 127) {
            bytesInRange = false
        }
    }
    println("nextBytes in Byte range: $bytesInRange")

    println("OK")
}
