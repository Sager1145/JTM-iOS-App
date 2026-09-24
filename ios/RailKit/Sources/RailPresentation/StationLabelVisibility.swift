/// Native map label hierarchy. Connection count is a navigational importance
/// signal, not a claim about passenger volume or a station's official rank.
public enum StationLabelVisibility {
    public static func minimumMapLibreZoom(lineCount: Int, isTerminal: Bool) -> Double {
        // Major hubs may label even a national overview; the renderer still
        // requires their railway to be drawn and their text to fit.
        if lineCount >= 4 { return 0 }
        if lineCount >= 3 { return 8 }
        if lineCount >= 2 { return 9 }
        return isTerminal ? 10 : 12
    }
}
