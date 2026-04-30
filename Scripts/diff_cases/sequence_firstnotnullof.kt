fun main() {
    val values = sequenceOf(1, 2, 3, 4)
    println(values.firstNotNullOf<String> { value ->
        if (value == 3) "three" else null
    })

    try {
        println(sequenceOf(1, 2).firstNotNullOf<String> { value ->
            if (value == 99) "hit" else null
        })
    } catch (e: Throwable) {
        println("missing")
    }
}
