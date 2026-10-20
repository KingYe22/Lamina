import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2, let pid = Int32(CommandLine.arguments[1]) else {
    fputs("usage: smoke-windows <pid>\n", stderr)
    exit(2)
}

let info = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as NSArray? ?? []
var matched = 0
for case let item as NSDictionary in info {
    let owner = (item[kCGWindowOwnerPID] as? NSNumber)?.int32Value ?? -1
    guard owner == pid else { continue }
    matched += 1
    let name = item[kCGWindowName] as? String ?? ""
    let layer = (item[kCGWindowLayer] as? NSNumber)?.intValue ?? -1
    fputs("window layer=\(layer) name=\(name)\n", stderr)
}
print(matched)
exit(matched > 0 ? 0 : 1)
