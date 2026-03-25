import kotlinx.coroutines.*

fun main() = runBlocking {
    // Test basic withContext functionality
    println("Main start")
    
    // Test withContext switching to Default dispatcher
    withContext(Dispatchers.Default) {
        println("Inside withContext Default")
        delay(100)
        println("After delay in Default")
    }
    
    println("Back to main")
    
    // Test withContext with result
    val result = withContext(Dispatchers.IO) {
        println("Inside withContext IO")
        "Hello from IO context"
    }
    
    println("Result from IO context: $result")
    println("Main end")
}
