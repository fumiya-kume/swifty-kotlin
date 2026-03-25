fun main() {
    // Test KClass functionality
    val stringClass = String::class
    val intClass = Int::class
    val listClass = List::class
    
    println("String::class: $stringClass")
    println("Int::class: $intClass")
    println("List::class: $listClass")
    
    // Test KClass methods
    println("String simpleName: ${stringClass.simpleName}")
    println("Int simpleName: ${intClass.simpleName}")
    
    // Test isInstance
    println("stringClass.isInstance(\"hello\"): ${stringClass.isInstance("hello")}")
    println("intClass.isInstance(42): ${intClass.isInstance(42)}")
    
    // Test typeOf
    val stringType = typeOf<String>()
    val intType = typeOf<Int>()
    
    println("typeOf<String>(): $stringType")
    println("typeOf<Int>(): $intType")
    
    // Test KType from KClass
    val stringKType: KType = stringClass.type
    val intKType: KType = intClass.type
    
    println("String KType: $stringKType")
    println("Int KType: $intKType")
}
