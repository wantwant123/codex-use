import AppKit
import Testing
@testable import agent_battery

struct MenuBarHealthImageTests {
    @Test @MainActor func statusLightsContainColorAndReuseBoundedImages() throws {
        let states: [(ProxyHealthKind, Int)] = [
            (.healthy, 1), (.slow, 0), (.partial, 0), (.retrying, 0),
            (.checking, 0), (.unknown, 0), (.stale, 0), (.failed, 2), (.unavailable, 2)
        ]
        var images = Set<ObjectIdentifier>()
        for (kind, expectedColor) in states {
            let indicator = ProxyHealthIndicator(health: ProxyHealth(kind: kind))
            let image = indicator.menuBarImage
            images.insert(ObjectIdentifier(image))
            #expect(!image.isTemplate)
            #expect(image.size == NSSize(width: 14, height: 14))
            #expect(image === indicator.menuBarImage)
            let data = try #require(image.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: data))
            let center = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
            #expect(center.alphaComponent > 0.9)
            switch expectedColor {
            case 1: #expect(center.greenComponent > center.redComponent && center.greenComponent > center.blueComponent)
            case 2: #expect(center.redComponent > center.greenComponent * 1.5)
            default: #expect(center.redComponent > center.greenComponent && center.greenComponent > center.blueComponent)
            }
        }
        #expect(images.count == 3)
    }
}
