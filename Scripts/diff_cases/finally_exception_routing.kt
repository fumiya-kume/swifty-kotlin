fun routeWithFinally(): String {
    try {
        println("Before try block")
        try {
            println("Inside inner try")
            return "inner return"
        } finally {
            println("Inner finally - should execute before return")
        }
    } catch (e: Exception) {
        println("Caught exception: $e")
    } finally {
        println("Outer finally - should execute after try-catch")
    }
}

fun main() {
    val result = routeWithFinally()
    println("Result: $result")
    println("After all blocks")
}
