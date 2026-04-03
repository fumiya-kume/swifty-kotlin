import kotlin.experimental.ExperimentalTypeInference

@ExperimentalTypeInference
fun <T> collect(builderAction: MutableList<T>.() -> Unit): List<T> = buildList(builderAction)

@ExperimentalTypeInference
fun <K, V> collectMap(builderAction: MutableMap<K, V>.() -> Unit): Map<K, V> = buildMap(builderAction)

fun main() {
    val numbers = collect {
        add(1)
        add(2)
        add(3)
    }

    val labels = collectMap {
        put(1, "one")
        put(2, "two")
    }

    val generated = sequence {
        yield(numbers[0])
        yieldAll(numbers)
    }

    println(numbers[0] + generated.first())
    println(labels[2] ?: "missing")
}
