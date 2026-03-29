import kotlin.time.*

fun main() {
    // Instant.now() / fromEpochMilliseconds
    val now = Instant.now()
    val epoch = Instant.fromEpochMilliseconds(0L)

    // epochSeconds and nanoOfSecond properties
    val epochSec = epoch.epochSeconds
    val epochNano = epoch.nanoOfSecond
    println(epochSec)   // 0
    println(epochNano)  // 0

    // Instant arithmetic: plus/minus Duration
    val d = 5.seconds
    val later = now + d
    val earlier = now - d

    // comparisons
    println(epoch < now)    // true
    println(now > epoch)    // true
    println(epoch <= epoch) // true
    println(epoch >= epoch) // true
    println(epoch == epoch) // true

    // until() — duration between two Instants
    val t1 = Instant.fromEpochMilliseconds(1000L)
    val t2 = Instant.fromEpochMilliseconds(3000L)
    val diff = t1.until(t2)
    println(diff.inWholeSeconds) // 2
}
