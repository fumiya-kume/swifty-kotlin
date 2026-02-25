package golden.sema

interface X {
    fun action(): String = "X"
}

interface Y {
    fun action(): String = "Y"
}

class Z : X, Y {
}
