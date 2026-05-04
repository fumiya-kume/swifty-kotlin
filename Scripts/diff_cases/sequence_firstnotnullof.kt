fun main() {
    val values = sequenceOf(1, 2, 3)

    println(values.firstNotNullOf { value ->
        if (value == 3) "three" else null
    })
    try {
        println(values.firstNotNullOf { value ->
            if (value == 9) "nine" else null
        })
    } catch (e: NoSuchElementException) {
        println("missing")
    }
}
