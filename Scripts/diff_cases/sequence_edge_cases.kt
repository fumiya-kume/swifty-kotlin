fun main() {
    val trace = mutableListOf<String>()

    val generated = generateSequence(1) { current ->
        trace.add("next:$current")
        if (current >= 3) null else current + 1
    }

    println(generated.take(2).toList())
    println(trace.joinToString(","))

    trace.clear()

    val filtered = sequenceOf(1, 2, 3, 4)
        .map {
            trace.add("map:$it")
            it * 2
        }
        .filter {
            trace.add("filter:$it")
            it % 4 == 0
        }

    println(filtered.take(1).toList())
    println(trace.joinToString(","))
}
