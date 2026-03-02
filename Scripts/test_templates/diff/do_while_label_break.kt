fun main() {
    // Basic do-while (first-run guarantee)
    var count = 0
    do {
        count += 1
        println(count)
    } while (count < 3)

    // Labeled do-while with break
    var x = 0
    outer@ do {
        x += 1
        if (x == 2) break@outer
        println("outer: $x")
    } while (x < 5)

    // Labeled do-while with continue
    var y = 0
    cont@ do {
        y += 1
        if (y < 3) continue@cont
        println("cont: $y")
    } while (y < 4)

    // Inline do-while body
    var z = 0
    do z = z + 1 while (z < 3)
    println("inline: $z")

    // Condition can reference body-local declarations
    var loops = 0
    do {
        val local = loops + 1
        println("local: $local")
        loops = local
    } while (local < 2)

    println("final: $count, x: $x, y: $y, loops: $loops")
}
