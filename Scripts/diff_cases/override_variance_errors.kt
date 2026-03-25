// Error cases for override variance - these should produce compilation errors

open class BaseClass {
    open fun publicMethod(): String = "public"
    protected open fun protectedMethod(): String = "protected"
    internal open fun internalMethod(): String = "internal"
}

// This class should cause visibility restriction errors
class ErrorClass : BaseClass() {
    override fun publicMethod(): String = "public override"  // OK: public -> public
    
    // ERROR: Cannot reduce visibility from protected to private
    private override fun protectedMethod(): String = "private override"
    
    // ERROR: Cannot reduce visibility from internal to private
    private override fun internalMethod(): String = "private override"
    
    // ERROR: Cannot reduce visibility from protected to private
    private override fun protectedMethod(): String = "private override"
}

// Test interface implementation with visibility errors
interface InterfaceBase {
    fun interfaceMethod(): String
    protected fun protectedMethod(): String
}

class InterfaceError : InterfaceBase {
    override fun interfaceMethod(): String = "ok"  // OK: public -> public
    
    // ERROR: Cannot reduce visibility from protected to private
    private override fun protectedMethod(): String = "error"
}

// Test abstract class implementation with visibility errors
abstract class AbstractBase {
    abstract fun abstractMethod(): String
    protected abstract fun protectedAbstract(): String
}

class AbstractError : AbstractBase() {
    override fun abstractMethod(): String = "ok"  // OK: public -> public
    
    // ERROR: Cannot reduce visibility from protected to private
    private override fun protectedAbstract(): String = "error"
}

// Multi-level inheritance with visibility errors
open class Level1Base {
    protected open fun level1Method(): String = "level1"
}

open class Level2Base : Level1Base() {
    public override fun level1Method(): String = "level2"  // OK: protected -> public
}

class Level3Error : Level2Base() {
    // ERROR: Cannot reduce visibility from public to private
    private override fun level1Method(): String = "level3"
}

// Test with different visibility combinations
open class VisibilityBase {
    open fun method1(): String = "public"
    protected open fun method2(): String = "protected"
    internal open fun method3(): String = "internal"
}

class VisibilityError : VisibilityBase() {
    // ERROR: Cannot reduce visibility from public to protected
    protected override fun method1(): String = "error1"
    
    // ERROR: Cannot reduce visibility from public to internal
    internal override fun method1(): String = "error2"
    
    // ERROR: Cannot reduce visibility from public to private
    private override fun method1(): String = "error3"
    
    // ERROR: Cannot reduce visibility from protected to private
    private override fun method2(): String = "error4"
    
    // ERROR: Cannot reduce visibility from internal to private
    private override fun method3(): String = "error5"
}
