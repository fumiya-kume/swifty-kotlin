// Integer division/remainder, rem vs mod, and floorDiv parity with kotlinc,
// including negative operands. Also Double rem/mod.
fun main() {
    println(7 / 2)
    println((-7) / 2)
    println(7 / (-2))
    println((-7) / (-2))
    println(7 % 2)
    println((-7) % 2)
    println(7 % (-2))
    println((-7) % (-2))

    println(5.rem(3))
    println((-5).rem(3))
    println(5.mod(3))
    println((-5).mod(3))
    println(5.mod(-3))
    println((-5).mod(-3))

    println(7.floorDiv(2))
    println((-7).floorDiv(2))
    println(7.floorDiv(-2))
    println((-7).floorDiv(-2))

    println((-7L).floorDiv(2L))
    println((-5L).mod(3L))

    println(5.5 % 2.0)
    println((-5.5) % 2.0)
    println(5.5.mod(2.0))
    println((-5.5).mod(2.0))
}
