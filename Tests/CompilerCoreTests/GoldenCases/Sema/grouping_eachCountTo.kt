fun render(values: List<String>) {
    val dest = mutableMapOf<Int, Int>()
    val result = values.groupingBy { it.length }.eachCountTo(dest)
}
