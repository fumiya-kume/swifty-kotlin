import kotlinx.coroutines.*

fun main() {
    // Test basic withContext functionality
    println("Main thread: ${Thread.currentThread().name}")
    
    // Test withContext switching to Default dispatcher
    withContext(Dispatchers.Default) {
        println("Inside withContext Default: ${Thread.currentThread().name}")
        delay(100)
        println("After delay in Default: ${Thread.currentThread().name}")
    }
    
    println("Back to main: ${Thread.currentThread().name}")
    
    // Test withContext with result
    val result = withContext(Dispatchers.IO) {
        println("Inside withContext IO: ${Thread.currentThread().name}")
        "Hello from IO context"
    }
    
    println("Result from IO context: $result")
    println("Final thread: ${Thread.currentThread().name}")
}
