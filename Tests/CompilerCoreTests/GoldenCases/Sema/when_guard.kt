fun classify(x: Any): String {
    return when (x) {
        is String if x.length > 3 -> "long string"
        is String -> "short string"
        is Int if x > 0 -> "positive int"
        is Int -> "non-positive int"
        else -> "other"
    }
}
