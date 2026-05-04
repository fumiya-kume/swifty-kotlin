fun main() {
    val values = sequenceOf(1, 2, 3)
    println(values.firstNotNullOf { value ->
        if (value == 3) "three" else null
    })

    try {
        println(sequenceOf(1, 2).firstNotNullOf { value ->
            if (value == 3) "three" else null
        })
    } catch (_: NoSuchElementException) {
        println("missing")
    }
}
