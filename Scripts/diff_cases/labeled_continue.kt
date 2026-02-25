fun main() {
    outer@ for (i in 1..3) {
        for (j in 1..3) {
            if (j == 2) continue@outer
            println(j)
        }
    }
    println("after continue test")
}
