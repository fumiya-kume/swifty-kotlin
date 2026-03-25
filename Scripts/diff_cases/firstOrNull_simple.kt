fun main() {
    // Simple firstOrNull tests based on working patterns
    
    println("=== List firstOrNull Tests ===")
    
    val list = listOf(1, 2, 3)
    val empty = emptyList<Int>()
    
    println("list.firstOrNull(): ${list.firstOrNull()}")
    println("empty.firstOrNull(): ${empty.firstOrNull()}")
    
    println("\n=== String firstOrNull Tests ===")
    
    val str = "hello"
    val emptyStr = ""
    
    println("str.firstOrNull(): ${str.firstOrNull()}")
    println("emptyStr.firstOrNull(): ${emptyStr.firstOrNull()}")
    
    println("\n=== Single Element Tests ===")
    
    val singleList = listOf(42)
    val singleStr = "a"
    
    println("singleList.firstOrNull(): ${singleList.firstOrNull()}")
    println("singleStr.firstOrNull(): ${singleStr.firstOrNull()}")
}
