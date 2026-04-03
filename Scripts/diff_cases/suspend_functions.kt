// STDLIB-CORO-068: suspend function basic implementation
// Tests: suspend fun declaration, runBlocking { } to call suspend fun from main
import kotlinx.coroutines.*

// Basic suspend function returning String
suspend fun greet(name: String): String {
    return "Hello, $name!"
}

// Suspend function returning Int
suspend fun add(a: Int, b: Int): Int {
    return a + b
}

// Suspend function with no return value (Unit)
suspend fun printMessage(msg: String) {
    println(msg)
}

// Suspend function calling another suspend function
suspend fun greetAndAdd(name: String, x: Int, y: Int): String {
    val greeting = greet(name)
    val sum = add(x, y)
    return "$greeting Sum=$sum"
}

// Suspend function type invocation with 0 and 1 arguments
suspend fun invokeZero(block: suspend () -> Int): Int {
    return block()
}

suspend fun invokeOne(block: suspend (Int) -> Int): Int {
    return block(41)
}

fun main() = runBlocking {
    // Test basic suspend function returning String
    val greeting = greet("World")
    println(greeting)

    // Test suspend function returning Int
    val result = add(3, 4)
    println(result)

    // Test suspend function with Unit return
    printMessage("suspend unit function works")

    // Test suspend function calling another suspend function
    val combined = greetAndAdd("Kotlin", 10, 20)
    println(combined)

    // Test suspend function type invocation with 0 and 1 arguments
    println(invokeZero { 7 })
    println(invokeOne { value -> value + 1 })

    println("done")
}
