fun main() {
    // Basic do-while (first-run guarantee)
    var count = 0
    do {
        count++
        println(count)
    } while (count < 3)

    // Labeled do-while with break
    var x = 0
    outer@ do {
        x++
        if (x == 2) break@outer
        println("outer: $x")
    } while (x < 5)

    println("final: $count, x: $x")
}
