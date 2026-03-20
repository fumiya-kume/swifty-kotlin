fun main() {
    // Basic: named parameter
    repeat(4) { index ->
        println(index)
    }

    // Basic: implicit it
    repeat(3) {
        println(it)
    }

    // String interpolation with it
    repeat(3) {
        println("i=$it")
    }

    // Zero times: body never executes
    repeat(0) {
        println("never")
    }

    // Single iteration
    repeat(1) {
        println("once")
    }

    // Accumulator pattern
    var sum = 0
    repeat(5) {
        sum += it
    }
    println(sum)

    // Nested repeat
    repeat(2) { i ->
        repeat(3) { j ->
            println("$i,$j")
        }
    }

    // return@repeat acts like continue
    repeat(5) {
        if (it == 2) return@repeat
        println("skip2: $it")
    }

    // Expression as times argument
    val n = 3
    repeat(n + 1) {
        println("expr: $it")
    }

    // Negative times: body never executes (Kotlin stdlib treats negative as 0)
    repeat(-1) {
        println("negative")
    }
    println("after negative")

    // Large iteration count (just verify it runs)
    var count = 0
    repeat(1000) {
        count++
    }
    println("count=$count")
}
