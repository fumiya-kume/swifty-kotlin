import kotlin.math.abs
import kotlin.random.Random

data class PropertyStats(
    val checked: Int,
    val failures: Int,
    val shrinks: Int,
    val minimizedCounterexample: Int?
)

private fun seededSamples(seed: Int, count: Int): List<Int> {
    val random = Random(seed)
    val samples = mutableListOf<Int>()
    var index = 0
    while (index < count) {
        samples.add(random.nextInt(-32, 33))
        index += 1
    }
    return samples
}

private fun shrinkTowardZero(value: Int): Int? {
    if (value == 0) {
        return null
    }
    val next = value / 2
    return if (next == value) null else next
}

private fun runPropertyCheck(samples: List<Int>, predicate: (Int) -> Boolean): PropertyStats {
    var checked = 0
    var shrinks = 0

    for (sample in samples) {
        checked += 1
        if (predicate(sample)) {
            continue
        }

        var current = sample
        var minimized = sample

        while (true) {
            val next = shrinkTowardZero(current) ?: break
            if (next == current) {
                break
            }
            if (predicate(next)) {
                break
            }

            shrinks += 1
            minimized = next
            current = next
        }

        return PropertyStats(
            checked = checked,
            failures = 1,
            shrinks = shrinks,
            minimizedCounterexample = minimized
        )
    }

    return PropertyStats(
        checked = checked,
        failures = 0,
        shrinks = 0,
        minimizedCounterexample = null
    )
}

fun main() {
    val repeatedA = seededSamples(seed = 2026, count = 8)
    val repeatedB = seededSamples(seed = 2026, count = 8)
    println("seeded samples deterministic: ${repeatedA == repeatedB}")

    val successSamples = seededSamples(seed = 42, count = 32)
    val success = runPropertyCheck(successSamples) { sample -> sample + 0 == sample }
    println("success checked: ${success.checked}")
    println("success failures: ${success.failures}")
    println("success shrinks: ${success.shrinks}")
    println("success minimized: ${success.minimizedCounterexample}")

    val failingSamples = listOf(13) + seededSamples(seed = 31415, count = 15).map { abs(it % 17) * 2 + 1 }
    val failure = runPropertyCheck(failingSamples) { sample -> sample == 0 }
    println("failure checked: ${failure.checked}")
    println("failure failures: ${failure.failures}")
    println("failure shrinks: ${failure.shrinks}")
    println("failure minimized: ${failure.minimizedCounterexample}")
}
