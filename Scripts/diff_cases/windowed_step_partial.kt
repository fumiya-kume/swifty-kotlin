fun main() {
    val list = listOf(1, 2, 3, 4, 5)

    // 1-arg: windowed(size) defaults step=1, partialWindows=false
    println(list.windowed(3))

    // 2-arg: windowed(size, step)
    println(list.windowed(3, 2))

    // 3-arg: windowed(size, step, partialWindows=true)
    println(list.windowed(3, 2, true))
    println(list.windowed(2, 3, false))

    // String variants
    val s = "abcdefgh"
    println(s.windowed(3))
    println(s.windowed(3, 2))
    println(s.windowed(3, 2, true))
    println(s.windowed(4, 3, false))
}
