fun main() {
    outer@ for (i in 1..3) {
        for (j in 1..3) {
            if (j == 2) break@outer
            println(j)
        }
    }
    println("after outer for")

    loop@ while (true) {
        println("in while")
        break@loop
    }
    println("after while")

    outer@ for (i in 1..3) {
        for (j in 1..3) {
            if (j == 2) continue@outer
            println(j)
        }
    }
    println("after continue test")
}
