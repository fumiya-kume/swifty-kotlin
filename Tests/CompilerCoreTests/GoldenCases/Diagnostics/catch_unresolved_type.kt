fun catchUndefined() {
    try {
        throw Exception("test")
    } catch (e: NonExistentException) {
        println("caught")
    }
}
