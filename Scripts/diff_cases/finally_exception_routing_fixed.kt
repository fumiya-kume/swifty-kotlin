fun main() {
    try {
        println("Before try block")
        try {
            println("Inside inner try")
            // Just return without value to test finally execution order
            return@label "inner return"
        } finally {
            println("Inner finally - should execute before return")
        }
    } catch (e: Exception) {
        println("Caught exception: $e")
    } finally {
        println("Outer finally - should execute after try-catch")
    }
    
    println("After all blocks")
}
