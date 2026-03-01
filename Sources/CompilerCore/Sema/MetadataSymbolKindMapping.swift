import Foundation

func symbolKindFromMetadataToken(_ token: String) -> SymbolKind? {
    switch token {
    case "package":
        return .package
    case "class":
        return .class
    case "interface":
        return .interface
    case "object":
        return .object
    case "enumClass":
        return .enumClass
    case "annotationClass":
        return .annotationClass
    case "typeAlias":
        return .typeAlias
    case "function":
        return .function
    case "constructor":
        return .constructor
    case "property":
        return .property
    case "field":
        return .field
    case "backingField":
        return .backingField
    case "typeParameter":
        return .typeParameter
    case "valueParameter":
        return .valueParameter
    case "local":
        return .local
    case "label":
        return .label
    default:
        return nil
    }
}
