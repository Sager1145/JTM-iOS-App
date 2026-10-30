import CoreGraphics
import Foundation
let want = CommandLine.arguments[1]
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list {
  if let pid = w[kCGWindowOwnerPID as String] as? Int, String(pid) == want,
     let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
     let b = w[kCGWindowBounds as String] as? [String: Any], let h = b["Height"] as? Double, h > 300 {
    print(w[kCGWindowNumber as String]!); break
  }
}
