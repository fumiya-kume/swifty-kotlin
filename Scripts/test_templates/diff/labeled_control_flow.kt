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
}
