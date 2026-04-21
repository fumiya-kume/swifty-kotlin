package golden.sema

fun useRemoveRangeIndices(): String = "hello world".removeRange(5, 11)

fun useRemoveRangeStart(): String = "hello world".removeRange(0, 6)

fun useRemoveRangeEmpty(): String = "hello".removeRange(2, 2)

fun useRemoveRangeIntRange(): String = "hello world".removeRange(5..10)
