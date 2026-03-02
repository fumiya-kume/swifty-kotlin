fun main() {
    // 1. break@outer from nested for loop
    outer@ for (i in 1..3) {
        for (j in 1..3) {
            if (j == 2) break@outer
            println(j)
        }
    }
    println("after outer for")

    // 2. break@loop from labeled while
    loop@ while (true) {
        println("in while")
        break@loop
    }
    println("after while")

    // 3. continue@outer from nested for loop
    outer@ for (i in 1..3) {
        for (j in 1..3) {
            if (j == 2) continue@outer
            println(j)
        }
    }
    println("after continue test")

    // 4. return@label from labeled lambda (local return)
    val items = listOf(1, 2, 3, 4, 5)
    items.forEach lit@{
        if (it == 3) return@lit
        println(it)
    }
    println("after lambda return")
}
