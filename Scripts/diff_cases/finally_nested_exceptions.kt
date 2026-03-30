fun main() {
    try {
        println("Outer try")
        try {
            println("Middle try - will throw")
            throw RuntimeException("Middle exception")
        } catch (e: Exception) {
            println("Middle catch: ${e.message}")
            try {
                println("Inner try - will throw")
                throw IllegalArgumentException("Inner exception")
            } finally {
                println("Inner finally - should execute")
            }
        } finally {
            println("Middle finally - should execute")
        }
    } catch (e: Exception) {
        println("Outer catch: ${e.message}")
    } finally {
        println("Outer finally - should execute")
    }
    
    println("After all blocks")
}
