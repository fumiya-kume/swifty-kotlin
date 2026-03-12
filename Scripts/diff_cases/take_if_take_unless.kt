fun main() {
    // takeIf: returns receiver if predicate is true, else null
    println(10.takeIf { it > 5 })   // 10
    println(10.takeIf { it > 20 })  // null
    println(0.takeIf { it == 0 })   // 0

    // takeUnless: returns receiver if predicate is false, else null
    println(10.takeUnless { it > 5 })   // null
    println(10.takeUnless { it > 20 })  // 10
    println(0.takeUnless { it != 0 })  // 0
}
