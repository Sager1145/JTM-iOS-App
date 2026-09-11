import AppKit
import ApplicationServices
import Vision
import ImageIO

func fail(_ s: String) -> Never { fputs(s + "\n", stderr); exit(1) }
func attr(_ e: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?; AXUIElementCopyAttributeValue(e, key as CFString, &value); return value
}
func str(_ e: AXUIElement, _ key: String) -> String { attr(e,key) as? String ?? "" }
func children(_ e: AXUIElement) -> [AXUIElement] { attr(e,kAXChildrenAttribute) as? [AXUIElement] ?? [] }
func walk(_ e: AXUIElement, _ depth: Int = 0) -> [AXUIElement] {
    if depth > 32 { return [] }; return [e] + children(e).flatMap { walk($0, depth + 1) }
}
func rect(_ e: AXUIElement) -> [Double] {
    var p = CGPoint.zero; var s = CGSize.zero
    if let v = attr(e,kAXPositionAttribute) { AXValueGetValue(v as! AXValue,.cgPoint,&p) }
    if let v = attr(e,kAXSizeAttribute) { AXValueGetValue(v as! AXValue,.cgSize,&s) }
    return [p.x,p.y,s.width,s.height]
}
func emit(_ value: Any) { let d = try! JSONSerialization.data(withJSONObject:value, options:[.sortedKeys]); print(String(data:d,encoding:.utf8)!) }
let args = Array(CommandLine.arguments.dropFirst())
if args.first == "session" {
    let session = CGSessionCopyCurrentDictionary() as? [String:Any] ?? [:]
    emit(["locked":session["CGSSessionScreenIsLocked"] as? Bool ?? false,
          "on_console":session[kCGSessionOnConsoleKey as String] as? Bool ?? false])
    exit(0)
}
if args.first == "ocr" {
    guard args.count == 2, let source = CGImageSourceCreateWithURL(URL(fileURLWithPath:args[1]) as CFURL,nil), let cg = CGImageSourceCreateImageAtIndex(source,0,nil) else { fail("Cannot read image") }
    let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
    request.recognitionLanguages = ["en-US", "zh-Hant"]
    do { try VNImageRequestHandler(cgImage:cg).perform([request]) } catch { fail("Vision OCR failed: \(error)") }
    emit((request.results ?? []).compactMap { o -> [String:Any]? in
        guard let t = o.topCandidates(1).first else { return nil }
        var words: [[String:Any]] = []
        let regex = try! NSRegularExpression(pattern:"[0-9]+(?:\\.[0-9]+)?|[A-Za-z]+|[公尺米公里]+")
        for match in regex.matches(in:t.string, range:NSRange(t.string.startIndex...,in:t.string)) {
            if let range = Range(match.range,in:t.string), let bb = try? t.boundingBox(for:range) {
                words.append(["text":String(t.string[range]),"box":[bb.boundingBox.minX,1-bb.boundingBox.maxY,bb.boundingBox.width,bb.boundingBox.height]])
            }
        }
        return ["text":t.string,"words":words,"confidence":t.confidence,"box":[o.boundingBox.minX, 1-o.boundingBox.maxY, o.boundingBox.width,o.boundingBox.height]]
    }); exit(0)
}
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.Maps").first else { fail("Apple Maps is not running") }
guard AXIsProcessTrusted() else { fail("Accessibility access is required for the terminal running this script. Enable it in System Settings > Privacy & Security > Accessibility, then retry.") }
let root = AXUIElementCreateApplication(app.processIdentifier)
let elements = walk(root)
if args.first == "cancel-menu" {
    for e in elements where str(e,kAXRoleAttribute) == "AXMenu" { AXUIElementPerformAction(e,kAXCancelAction as CFString) }
    exit(0)
}
if args.first == "press" {
    guard args.count == 2 else { fail("press needs an exact AX identifier, description, or title") }
    guard let e = elements.first(where:{ str($0,kAXIdentifierAttribute) == args[1] || str($0,kAXDescriptionAttribute) == args[1] || str($0,kAXTitleAttribute) == args[1] }) else { fail("Control not found: " + args[1]) }
    let result = AXUIElementPerformAction(e,kAXPressAction as CFString)
    guard result == .success else { fail("AXPress failed: \(result.rawValue)") }; exit(0)
}
if args.first == "info" || args.isEmpty {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
    let own = windows.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0 }
    let window = own.max { a,b in
        let aa = a[kCGWindowBounds as String] as? [String:Double] ?? [:]; let bb = b[kCGWindowBounds as String] as? [String:Double] ?? [:]
        return (aa["Width"] ?? 0)*(aa["Height"] ?? 0) < (bb["Width"] ?? 0)*(bb["Height"] ?? 0)
    }
    guard let window else { fail("No visible Maps window") }
    emit(["pid":app.processIdentifier,"window_id":window[kCGWindowNumber as String]!,"window_bounds":window[kCGWindowBounds as String]!,"screen_recording":CGPreflightScreenCaptureAccess(),"elements":elements.compactMap { e -> [String:Any]? in
        let id = str(e,kAXIdentifierAttribute); let val = str(e,kAXValueAttribute); let role = str(e,kAXRoleAttribute)
        if id == "HomeView" || id == "SearchHomeView" || id == "VKPointFeature" || role == "AXButton" || role == "AXMenuBarItem" || role == "AXMenuItem" || val.contains("VKMapType") {
            var names: CFArray?; AXUIElementCopyAttributeNames(e,&names)
            return ["id":id,"role":role,"title":str(e,kAXTitleAttribute),"description":str(e,kAXDescriptionAttribute),"value":val,"rect":rect(e),"attributes":names as? [String] ?? []]
        }; return nil
    }]); exit(0)
}
fail("Usage: native info | press EXACT_LABEL | ocr IMAGE")
