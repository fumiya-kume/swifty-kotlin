import Foundation

extension LLVMBackend {
    struct FrameMapPlan {
        let parameterSlotBySymbol: [SymbolID: Int]
        let exprSlotByID: [Int32: Int]
        let rootOffsets: [Int32]

        static let empty = FrameMapPlan(
            parameterSlotBySymbol: [:],
            exprSlotByID: [:],
            rootOffsets: []
        )

        var rootCount: Int {
            rootOffsets.count
        }
    }

    func frameMapDescriptorSymbol(for function: KIRFunction) -> String {
        "kk_frame_map_\(max(0, Int(function.symbol.rawValue)))"
    }

    func frameMapOffsetsSymbol(for function: KIRFunction) -> String {
        "kk_frame_map_offsets_\(max(0, Int(function.symbol.rawValue)))"
    }

    func buildFrameMapPlan(function: KIRFunction) -> FrameMapPlan {
        var parameterSlotBySymbol: [SymbolID: Int] = [:]
        var nextSlot = 0
        for parameter in function.params {
            parameterSlotBySymbol[parameter.symbol] = nextSlot
            nextSlot += 1
        }

        let exprIDs = collectFrameRootExprIDs(function: function)
        var exprSlotByID: [Int32: Int] = [:]
        for exprID in exprIDs {
            exprSlotByID[exprID.rawValue] = nextSlot
            nextSlot += 1
        }

        let pointerStride = max(1, MemoryLayout<Int>.size)
        let rootOffsets = (0..<nextSlot).map { slot in
            Int32(slot * pointerStride)
        }

        return FrameMapPlan(
            parameterSlotBySymbol: parameterSlotBySymbol,
            exprSlotByID: exprSlotByID,
            rootOffsets: rootOffsets
        )
    }

    func collectFrameRootExprIDs(function: KIRFunction) -> [KIRExprID] {
        var ids: Set<KIRExprID> = []

        for instruction in function.body {
            switch instruction {
            case .jumpIfEqual(let lhs, let rhs, _):
                ids.insert(lhs)
                ids.insert(rhs)
            case .constValue(let result, _):
                ids.insert(result)
            case .binary(_, let lhs, let rhs, let result):
                ids.insert(lhs)
                ids.insert(rhs)
                ids.insert(result)
            case .call(_, _, let arguments, let result, _, let thrownResult):
                for arg in arguments {
                    ids.insert(arg)
                }
                if let result {
                    ids.insert(result)
                }
                if let thrownResult {
                    ids.insert(thrownResult)
                }
            case .jumpIfNotNull(let value, _):
                ids.insert(value)
            case .copy(let from, let to):
                ids.insert(from)
                ids.insert(to)
            case .rethrow(let value):
                ids.insert(value)
            case .returnIfEqual(let lhs, let rhs):
                ids.insert(lhs)
                ids.insert(rhs)
            case .returnValue(let value):
                ids.insert(value)
            default:
                continue
            }
        }

        return ids.sorted(by: { $0.rawValue < $1.rawValue })
    }
}
