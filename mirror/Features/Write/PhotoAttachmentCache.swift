#if os(iOS)
import ImageIO
import UIKit

/// The editor's photo attachments: each photo decoded once, downsampled to the size it's drawn
/// at, and reused by later re-renders. Laid out exactly as before: a photo is shown at its
/// pixel width in points, capped at the line width (`UIImage(data:)` has scale 1).
struct PhotoAttachmentCache {
    struct Photo {
        let image: UIImage
        /// Point size the attachment is laid out at (the old `UIImage(data:)` rule).
        let displaySize: CGSize
    }

    /// Identifies a photo's bytes without hashing all of them on every render.
    private struct Fingerprint: Equatable {
        let count: Int
        let head: Int
        let tail: Int

        init(_ data: Data) {
            count = data.count
            head = data.prefix(512).hashValue
            tail = data.suffix(512).hashValue
        }
    }

    private struct Entry {
        let fingerprint: Fingerprint
        let maxWidth: CGFloat
        let photo: Photo?
    }

    private var entries: [Int: Entry] = [:]

    /// The decoded photo for `data` at photo index `index`, or nil when it doesn't decode.
    mutating func image(for data: Data, at index: Int, maxWidth: CGFloat, displayScale: CGFloat) -> Photo? {
        let fingerprint = Fingerprint(data)
        if let cached = entries[index], cached.fingerprint == fingerprint, cached.maxWidth == maxWidth {
            return cached.photo
        }
        let photo = Self.decode(data, maxWidth: maxWidth, displayScale: displayScale)
        entries[index] = Entry(fingerprint: fingerprint, maxWidth: maxWidth, photo: photo)
        return photo
    }

    /// Same answer the editor drew: the cached decode when there is one for these bytes, else
    /// whether the header describes an image.
    func isReadable(_ data: Data, at index: Int) -> Bool {
        if let cached = entries[index], cached.fingerprint == Fingerprint(data) { return cached.photo != nil }
        return Self.originalPixelSize(of: data) != nil
    }

    /// Oriented pixel size from the image header (no decode), or nil when the data isn't an image.
    static func originalPixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0, height > 0 else { return nil }
        // EXIF orientations 5–8 are rotated by 90°.
        let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    private static func decode(_ data: Data, maxWidth: CGFloat, displayScale: CGFloat) -> Photo? {
        guard let original = originalPixelSize(of: data),
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let scale = min(1, maxWidth / original.width)
        let displaySize = CGSize(width: original.width * scale, height: original.height * scale)
        // Enough pixels for the screen, never more than the original has.
        let maxPixel = Int(ceil(max(displaySize.width, displaySize.height) * displayScale))
        let longestSide = Int(max(original.width, original.height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixel, longestSide),
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return Photo(image: UIImage(cgImage: cgImage), displaySize: displaySize)
    }
}
#endif
