import RailApplication

// Localized labels belong to the app; RailApplication owns the import rules.
extension ImportPreflight.Mode {
    var titleKey: String {
        switch self {
        case .replaceAll: "data.modeReplace"
        case .append: "data.modeAppend"
        }
    }

    var detailKey: String {
        switch self {
        case .replaceAll: "data.modeReplaceDetail"
        case .append: "data.modeAppendDetail"
        }
    }
}
