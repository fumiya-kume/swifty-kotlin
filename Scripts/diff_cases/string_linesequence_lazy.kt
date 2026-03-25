fun main() {
    // Test lazy semantics of lineSequence()
    // lineSequence() should be lazy - lines are computed only when consumed
    
    val largeText = "line1\nline2\nline3\nline4\nline5"
    
    // Test 1: Take only first element - should not compute all lines
    val firstLine = largeText.lineSequence().first()
    println("First line: $firstLine")
    
    // Test 2: Take only first 2 elements - should be efficient
    val firstTwoLines = largeText.lineSequence().take(2).toList()
    println("First two lines: $firstTwoLines")
    
    // Test 3: Compare with lines() which computes all lines immediately
    val allLines = largeText.lines()
    println("All lines: $allLines")
    
    // Test 4: Empty string handling
    val emptySequence = "".lineSequence()
    println("Empty sequence first: ${emptySequence.firstOrNull()}")
    println("Empty sequence toList: ${emptySequence.toList()}")
    
    // Test 5: Single line without newline
    val singleLine = "single line"
    println("Single line sequence: ${singleLine.lineSequence().toList()}")
    println("Single line lines: ${singleLine.lines()}")
}
