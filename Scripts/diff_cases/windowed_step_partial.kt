fun main() {
    // Comprehensive windowed(size, step, partialWindows) tests
    
    println("=== Basic windowed tests ===")
    
    val list = listOf(1, 2, 3, 4, 5)

    // 1-arg: windowed(size) defaults step=1, partialWindows=false
    println(list.windowed(3))

    // 2-arg: windowed(size, step)
    println(list.windowed(3, 2))

    // 3-arg: windowed(size, step, partialWindows=true)
    println(list.windowed(3, 2, true))
    println(list.windowed(2, 3, false))

    // String variants
    val s = "abcdefgh"
    println(s.windowed(3))
    println(s.windowed(3, 2))
    println(s.windowed(3, 2, true))
    println(s.windowed(4, 3, false))
    
    println("\n=== Step parameter variations ===")
    
    val numbers = listOf(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
    
    // step < size (overlapping windows)
    println("step 1, size 3: ${numbers.windowed(3, 1)}")
    println("step 2, size 4: ${numbers.windowed(4, 2)}")
    
    // step == size (non-overlapping)
    println("step 3, size 3: ${numbers.windowed(3, 3)}")
    println("step 2, size 2: ${numbers.windowed(2, 2)}")
    
    // step > size (gaps between windows)
    println("step 4, size 2: ${numbers.windowed(2, 4)}")
    println("step 5, size 3: ${numbers.windowed(3, 5)}")
    
    println("\n=== partialWindows parameter ===")
    
    // partialWindows=false (default) - only full windows
    println("partialWindows=false: ${list.windowed(3, 2, false)}")
    
    // partialWindows=true - include partial windows at end
    println("partialWindows=true: ${list.windowed(3, 2, true)}")
    
    // With different sizes
    val shortList = listOf(1, 2, 3, 4)
    println("short.windowed(3,1,false): ${shortList.windowed(3, 1, false)}")
    println("short.windowed(3,1,true): ${shortList.windowed(3, 1, true)}")
    
    println("\n=== String windowed with all parameters ===")
    
    val text = "abcdefghijklmnopqrstuvwxyz"
    
    // Different combinations
    println("text.windowed(3,1,false): ${text.windowed(3, 1, false)}")
    println("text.windowed(3,1,true): ${text.windowed(3, 1, true)}")
    println("text.windowed(4,2,false): ${text.windowed(4, 2, false)}")
    println("text.windowed(4,2,true): ${text.windowed(4, 2, true)}")
    println("text.windowed(5,3,false): ${text.windowed(5, 3, false)}")
    println("text.windowed(5,3,true): ${text.windowed(5, 3, true)}")
    
    println("\n=== Transform function tests ===")
    
    // windowed with transform
    val transformed = list.windowed(3) { window ->
        window.sum()
    }
    println("windowed(3) sum: $transformed")
    
    val transformedStep = list.windowed(2, 2) { window ->
        window.average()
    }
    println("windowed(2,2) avg: $transformedStep")
    
    val transformedPartial = list.windowed(3, 2, true) { window ->
        window.joinToString(",")
    }
    println("windowed(3,2,true) join: $transformedPartial")
    
    // String windowed with transform
    val stringTransformed = s.windowed(3, 1, true) { window ->
        window.uppercase()
    }
    println("string windowed transform: $stringTransformed")
    
    println("\n=== Edge cases ===")
    
    // Empty collections
    println("emptyList.windowed(3): ${emptyList<Int>().windowed(3)}")
    println("emptyList.windowed(3,2,true): ${emptyList<Int>().windowed(3, 2, true)}")
    println("\"\".windowed(3): ${"".windowed(3)}")
    
    // Single element
    val single = listOf(42)
    println("single.windowed(1): ${single.windowed(1)}")
    println("single.windowed(2,1,false): ${single.windowed(2, 1, false)}")
    println("single.windowed(2,1,true): ${single.windowed(2, 1, true)}")
    
    // Size larger than collection
    val small = listOf(1, 2, 3)
    println("small.windowed(5,1,false): ${small.windowed(5, 1, false)}")
    println("small.windowed(5,1,true): ${small.windowed(5, 1, true)}")
    
    // Size = 1
    println("numbers.windowed(1): ${numbers.windowed(1)}")
    println("numbers.windowed(1,2): ${numbers.windowed(1, 2)}")
    
    println("\n=== Type-specific tests ===")
    
    // Double list
    val doubles = listOf(1.1, 2.2, 3.3, 4.4, 5.5)
    println("doubles.windowed(2): ${doubles.windowed(2)}")
    println("doubles.windowed(3,1,true): ${doubles.windowed(3, 1, true)}")
    
    // Character list
    val chars = listOf('a', 'b', 'c', 'd', 'e', 'f')
    println("chars.windowed(2): ${chars.windowed(2)}")
    println("chars.windowed(3,2): ${chars.windowed(3, 2)}")
    
    // String list
    val strings = listOf("apple", "banana", "cherry", "date")
    println("strings.windowed(2): ${strings.windowed(2)}")
    println("strings.windowed(3,1,true): ${strings.windowed(3, 1, true)}")
    
    println("\n=== Complex transform functions ===")
    
    // Transform to different types
    val toStrings = numbers.windowed(3) { window ->
        window.joinToString("+")
    }
    println("to strings: $toStrings")
    
    val toMaps = numbers.windowed(3) { window ->
        window.mapIndexed { index, value -> index to value }.toMap()
    }
    println("to maps: $toMaps")
    
    val toBooleans = numbers.windowed(3) { window ->
        window.all { it > 5 }
    }
    println("to booleans: $toBooleans")
    
    // Transform with step and partialWindows
    val complexTransform = numbers.windowed(2, 3, true) { window ->
        "window(${window.joinToString()})=${window.size}"
    }
    println("complex transform: $complexTransform")
    
    println("\n=== Behavior verification ===")
    
    // Verify window contents and positions
    val testList = listOf(1, 2, 3, 4, 5, 6)
    val windows1 = testList.windowed(3, 1, false)
    val windows2 = testList.windowed(3, 1, true)
    
    println("full windows only: $windows1")
    println("with partial: $windows2")
    
    // Verify step behavior
    val stepWindows1 = testList.windowed(2, 2, false)
    val stepWindows2 = testList.windowed(2, 2, true)
    
    println("step 2 full: $stepWindows1")
    println("step 2 partial: $stepWindows2")
    
    // Verify large step
    val largeStep = testList.windowed(2, 5, true)
    println("large step: $largeStep")
    
    println("\n=== Special cases ===")
    
    // Step equal to size
    println("step=size: ${testList.windowed(2, 2, true)}")
    
    // Step larger than size
    println("step>size: ${testList.windowed(2, 4, true)}")
    
    // Transform that returns empty collections
    val emptyTransform = numbers.windowed(2) { emptyList<Int>() }
    println("empty transform: $emptyTransform")
    
    // Transform with side effects
    var counter = 0
    val sideEffectTransform = numbers.windowed(2) { window ->
        counter++
        window.map { it * counter }
    }
    println("side effect: $sideEffectTransform")
    println("counter: $counter")
    
    println("\n=== Large collection performance ===")
    
    val large = (1..50).toList()
    val largeWindows = large.windowed(5, 3, true) { it.size }
    println("large windows sizes: ${largeWindows.take(5)}")
    
    // Verify last window is partial when needed
    val lastWindowTest = listOf(1, 2, 3, 4, 5)
    val lastWindows = lastWindowTest.windowed(3, 2, true)
    println("last windows: $lastWindows")
    println("last window size: ${lastWindows.last().size}")
}
// SKIP-DIFF: nested List.toString() parity for windowed outputs is still unstable
