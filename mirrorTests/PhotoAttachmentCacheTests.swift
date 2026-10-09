#if os(iOS)
import Testing
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import mirror

/// The editor's photo cache keeps the old layout rule (pixel width in points, capped at the
/// line width), decodes once, and re-decodes only when the bytes or the width change.
struct PhotoAttachmentCacheTests {
    private func jpeg(width: Int, height: Int, orientation: Int? = nil) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.orange.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        guard let orientation else { return image.jpegData(compressionQuality: 0.8)! }
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image.cgImage!, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    @Test func largePhotoIsCappedAtTheLineWidthWithItsAspectRatio() throws {
        var cache = PhotoAttachmentCache()
        let photoResult = cache.image(for: jpeg(width: 4032, height: 3024), at: 0, maxWidth: 374, displayScale: 3)
        let photo = try #require(photoResult)
        #expect(photo.displaySize.width == 374)
        #expect(abs(photo.displaySize.height - 374 * 3024 / 4032) < 0.5)
        #expect(photo.image.size.width * photo.image.scale <= 374 * 3 + 1, "downsampled, not full size")
    }

    @Test func smallPhotoKeepsItsPixelSizeInPointsLikeUIImageData() throws {
        var cache = PhotoAttachmentCache()
        let data = jpeg(width: 200, height: 100)
        let photoResult = cache.image(for: data, at: 0, maxWidth: 374, displayScale: 3)
        let photo = try #require(photoResult)
        #expect(photo.displaySize == UIImage(data: data)!.size)
    }

    @Test func rotatedPhotoUsesItsOrientedSize() throws {
        var cache = PhotoAttachmentCache()
        // EXIF 6 = rotated 90°: stored 400×200, shown 200×400.
        let photoResult = cache.image(for: jpeg(width: 400, height: 200, orientation: 6), at: 0, maxWidth: 374, displayScale: 3)
        let photo = try #require(photoResult)
        #expect(photo.displaySize == CGSize(width: 200, height: 400))
    }

    @Test func secondRenderReusesTheDecodedImage() throws {
        var cache = PhotoAttachmentCache()
        let data = jpeg(width: 800, height: 600)
        let firstResult = cache.image(for: data, at: 0, maxWidth: 374, displayScale: 3)
        let first = try #require(firstResult)
        let secondResult = cache.image(for: data, at: 0, maxWidth: 374, displayScale: 3)
        let second = try #require(secondResult)
        #expect(first.image === second.image)
        let otherWidthResult = cache.image(for: data, at: 0, maxWidth: 300, displayScale: 3)
        let otherWidth = try #require(otherWidthResult)
        #expect(otherWidth.image !== first.image, "a new line width decodes again")
        let replacedResult = cache.image(for: jpeg(width: 640, height: 480), at: 0, maxWidth: 300, displayScale: 3)
        let replaced = try #require(replacedResult)
        #expect(replaced.displaySize.width == 300 && abs(replaced.displaySize.height - 225) < 0.5, "new bytes at the same index decode again")
    }

    @Test func undecodableDataIsNotAnImage() {
        var cache = PhotoAttachmentCache()
        let junk = Data(repeating: 7, count: 64)
        let junkResult = cache.image(for: junk, at: 0, maxWidth: 374, displayScale: 3)
        #expect(junkResult == nil)
        #expect(!cache.isReadable(junk, at: 0))
        #expect(cache.isReadable(jpeg(width: 10, height: 10), at: 1))
    }
}
#endif
