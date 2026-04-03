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

    // Instant arithmetic: plus/minus Duration (deterministic with epoch base)
    val d = 5.seconds
    val later = epoch + d
    val earlier = epoch - d
    println(later.epochSeconds)   // 5
    println(later.nanoOfSecond)   // 0
    println(earlier.epochSeconds) // -5
    println(earlier.nanoOfSecond) // 0

    // comparisons
    println(epoch < now)    // true
    println(now > epoch)    // true
    println(epoch <= epoch) // true
    println(epoch >= epoch) // true
    println(epoch == epoch) // true
    val epoch2 = Instant.fromEpochMilliseconds(0L)
    println(epoch == epoch2) // true
    println(epoch.elapsed().inWholeSeconds > 0) // true

    // until() — duration between two Instants
    val t1 = Instant.fromEpochMilliseconds(1000L)
    val t2 = Instant.fromEpochMilliseconds(3000L)
    val diff = t1.until(t2)
    println(diff.inWholeSeconds) // 2
}
