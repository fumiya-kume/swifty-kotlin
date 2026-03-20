// SKIP-DIFF  -- requires first-class function parameters and invoke operator
fun apply(x: Int, f: (Int) -> Int): Int = f(x)

fun compose(f: (Int) -> Int, g: (Int) -> Int): (Int) -> Int = { x -> f(g(x)) }

fun main() {
    val double = { x: Int -> x * 2 }
    val addThree = { x: Int -> x + 3 }
    println(apply(5, double))
    println(apply(5, addThree))

    val doubleThenAdd = compose(addThree, double)
    println(doubleThenAdd(4))

    // Pass lambda that captures outer variable
    val offset = 100
    println(apply(5) { it + offset })

    // HOF with multiple captured vars
    val factor = 3
    val base = 10
    val transform = { x: Int -> x * factor + base }
    println(apply(7, transform))
}
