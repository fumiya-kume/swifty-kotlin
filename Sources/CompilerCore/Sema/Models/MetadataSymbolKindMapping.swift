import Foundation

func symbolKindFromMetadataToken(_ token: String) -> SymbolKind? {
    switch token {
    case "package":
        .package
    case "class":
        .class
    case "interface":
        .interface
    case "object":
        .object
    case "enumClass":
        .enumClass
    case "annotationClass":
        .annotationClass
    case "typeAlias":
        .typeAlias
    case "function":
        .function
    case "constructor":
        .constructor
    case "property":
        .property
    case "field":
        .field
    case "backingField":
        .backingField
    case "typeParameter":
        .typeParameter
    case "valueParameter":
        .valueParameter
    case "local":
        .local
    case "label":
        .label
    default:
        nil
    }
}
