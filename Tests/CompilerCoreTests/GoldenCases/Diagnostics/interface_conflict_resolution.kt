package golden.diagnostics

// STDLIB-INHERIT-020: Multiple interface inheritance conflict resolution diagnostics

interface Left {
    fun method(): String = "Left"
}

interface Right {
    fun method(): String = "Right"
}

// Error: must override method() because it inherits from both Left and Right
class MissingOverride : Left, Right
