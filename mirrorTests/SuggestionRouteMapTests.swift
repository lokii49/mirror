import CoreLocation
import Foundation
import Testing
import UIKit
@testable import mirror

#if canImport(JournalingSuggestions)
/// Draws a synthetic route the way a workout suggestion does and keeps the picture for review
/// (attachment). Needs map tiles from the network, so no map (offline, CI) is not a failure.
@Suite("Suggestion route map")
@MainActor
struct SuggestionRouteMapTests {
    @Test func aTrimmedRouteBecomesAPicture() async throws {
        guard #available(iOS 17.2, *) else { return }
        // A loop through a synthetic park, one point every ~50 m.
        let points = (0..<80).map { i -> CLLocation in
            let a = Double(i) / 80 * 2 * .pi
            return CLLocation(latitude: 38.72 + 0.006 * sin(a), longitude: -9.15 + 0.008 * cos(a) + Double(i) * 0.00004)
        }
        let trimmed = try #require(SuggestionLines.trimmedRoute(points))
        guard let url = await SuggestionInsert.routeMap(trimmed) else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try #require(UIImage(contentsOfFile: url.path))
        #expect(image.size.width == 1200 && image.size.height == 800)
        Attachment.record(try #require(image.jpegData(compressionQuality: 0.9)), named: "route-map.jpg")
    }

    @Test func aNamedPlaceBecomesAPinnedMap() async throws {
        guard #available(iOS 17.2, *) else { return }
        guard let url = await SuggestionInsert.placeMap(CLLocation(latitude: 38.7115, longitude: -9.1366)) else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try #require(UIImage(contentsOfFile: url.path))
        #expect(image.size.width == 1200 && image.size.height == 800)
        Attachment.record(try #require(image.jpegData(compressionQuality: 0.9)), named: "place-map.jpg")
    }
}
#endif
