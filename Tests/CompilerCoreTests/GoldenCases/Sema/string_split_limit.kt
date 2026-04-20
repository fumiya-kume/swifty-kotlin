fun main() {
    val a = "a,b,c,d".split(",", limit = 2)
    val b = "a,b,c,d".split(",", limit = 3)
    val c = "a,b,c,d".split(",")
    val d = "one::two::three".split("::", limit = 2)
}
