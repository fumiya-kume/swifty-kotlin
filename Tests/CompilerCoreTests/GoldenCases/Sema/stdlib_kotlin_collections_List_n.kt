fun checked(values: List<String?>): List<String> {
    return values.requireNoNulls()
}
