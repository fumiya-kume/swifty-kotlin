fun main() {
    val values = listOf("a", "bb", "ccc", "dddd")
    val comparator: Comparator<Any> = Comparator { left, right ->
        left.toString().length - right.toString().length
    }

    println(values.maxWith(comparator))
    println(values.maxWithOrNull(comparator))
    println(values.minWith(comparator))
    println(values.minWithOrNull(comparator))
    println(values.sortedWith(comparator))
    println(values.sortedByDescending { value ->
        if (value.length % 2 == 0) null else value.length
    })

    val mutableValues = mutableListOf("a", "bb", "ccc", "dddd")
    mutableValues.sortWith(comparator)
    println(mutableValues)
}
