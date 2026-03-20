fun main() {
    // let: transforms value, returns lambda result
    val letResult = 42.let { it * 2 }
    println(letResult)

    // let with nullable: safe call
    val nullStr: String? = null
    val letNull = nullStr?.let { it.length }
    println(letNull)
    val nonNullStr: String? = "hello"
    val letNonNull = nonNullStr?.let { it.length }
    println(letNonNull)

    // run: extension form, returns lambda result
    val runResult = "Kotlin".run { length + 10 }
    println(runResult)

    // run: non-extension form (just a block)
    val runBlock = run {
        val x = 10
        val y = 20
        x + y
    }
    println(runBlock)

    // with: returns lambda result
    val sb = StringBuilder()
    val withResult = with(sb) {
        append("Hello")
        append(" ")
        append("World")
        toString()
    }
    println(withResult)

    // apply: returns receiver
    val list = mutableListOf<Int>().apply {
        add(1)
        add(2)
        add(3)
    }
    println(list)

    // also: returns receiver, lambda receives it
    val alsoList = mutableListOf(10, 20, 30).also {
        println("Size: ${it.size}")
    }
    println(alsoList)

    // chaining scope functions
    val chained = "hello"
        .let { it.uppercase() }
        .also { println("After uppercase: $it") }
        .run { substring(0, 3) }
    println(chained)

    // let with explicit lambda parameter name
    val named = 100.let { value -> value + 50 }
    println(named)

    // apply on a data class-like scenario
    val map = HashMap<String, Int>().apply {
        put("a", 1)
        put("b", 2)
    }
    println(map.size)

    // nested scope functions
    val nested = "outer".let { outer ->
        "inner".let { inner ->
            "$outer-$inner"
        }
    }
    println(nested)
}
