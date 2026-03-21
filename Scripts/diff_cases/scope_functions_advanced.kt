fun main() {
    // let: transforms value, returns lambda result
    val letResult = 42.let { it * 2 }
    println(letResult)

    // let with nullable: safe call
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

    // also: returns receiver, lambda receives it
    val alsoList = mutableListOf(10, 20, 30).also {
        println("Size: ${it.size}")
    }
    println(alsoList)

    // let with explicit lambda parameter name
    val named = 100.let { value -> value + 50 }
    println(named)

    // let with string concatenation
    val concat = "hello".let { it + " world" }
    println(concat)
}
