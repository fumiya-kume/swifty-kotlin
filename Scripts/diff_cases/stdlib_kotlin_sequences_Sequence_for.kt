fun main() {
    var visited = ""
    sequenceOf(1, 2, 3).forEach {
        visited += it.toString()
    }
    println(visited)

    var indexed = ""
    sequenceOf("a", "b", "c").forEachIndexed { index, value ->
        if (indexed.isNotEmpty()) indexed += "|"
        indexed += "$index=$value"
    }
    println(indexed)

    var emptyCalls = 0
    emptySequence<Int>().forEach { emptyCalls += 1 }
    println("empty:$emptyCalls")

    try {
        sequenceOf(1, 2, 3).forEachIndexed { index, _ ->
            if (index == 1) throw IllegalStateException("stop")
        }
        println("returned")
    } catch (_: IllegalStateException) {
        println("threw")
    }
}
