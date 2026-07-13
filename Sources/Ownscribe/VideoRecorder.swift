import Foundation
import AVFoundation
import CoreMedia
import ScreenCaptureKit
import Combine

/// A selectable capture source: a whole display or a single window.
struct CaptureSource: Identifiable, Hashable {
    enum Kind: Hashable { case display, window }
    let id: String
    let name: String
    let kind: Kind
    // Kept out of Hashable via manual conformance below.
    let display: SCDisplay?
    let window: SCWindow?

    static func == (l: CaptureSource, r: CaptureSource) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// Captures a display or window to an H.264 .mp4 using ScreenCaptureKit +
/// AVAssetWriter. Video-only — ownscribe handles audio separately.
final class VideoRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var startedSession = false
    private let queue = DispatchQueue(label: "com.shyamzzp.ownscribe.video")
    private(set) var outputURL: URL?
    private var failure: String?

    var lastError: String? { failure }

    /// Enumerate shareable windows and displays.
    static func availableSources() async -> [CaptureSource] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            var sources: [CaptureSource] = []
            for d in content.displays {
                sources.append(CaptureSource(
                    id: "display-\(d.displayID)",
                    name: "Display \(d.displayID) (\(d.width)×\(d.height))",
                    kind: .display, display: d, window: nil))
            }
            for w in content.windows {
                guard let title = w.title, !title.isEmpty,
                      let app = w.owningApplication else { continue }
                if w.frame.width < 40 || w.frame.height < 40 { continue }
                sources.append(CaptureSource(
                    id: "window-\(w.windowID)",
                    name: "\(app.applicationName) — \(title)",
                    kind: .window, display: nil, window: w))
            }
            return sources
        } catch {
            return []
        }
    }

    /// Begin capturing the given source to `url`.
    func start(source: CaptureSource, to url: URL) async throws {
        failure = nil
        startedSession = false
        outputURL = url
        try? FileManager.default.removeItem(at: url)

        let filter: SCContentFilter
        let pxWidth: Int
        let pxHeight: Int

        if source.kind == .display, let display = source.display {
            filter = SCContentFilter(display: display, excludingWindows: [])
            pxWidth = display.width * 2
            pxHeight = display.height * 2
        } else if let window = source.window {
            filter = SCContentFilter(desktopIndependentWindow: window)
            pxWidth = Int(window.frame.width * 2)
            pxHeight = Int(window.frame.height * 2)
        } else {
            throw NSError(domain: "Ownscribe", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid capture source"])
        }

        let config = SCStreamConfiguration()
        config.width = max(2, pxWidth - (pxWidth % 2))
        config.height = max(2, pxHeight - (pxHeight % 2))
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30) // 30 fps
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        config.queueDepth = 6

        // AVAssetWriter → .mp4 (H.264)
        let w = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height,
        ]
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        vInput.expectsMediaDataInRealTime = true
        guard w.canAdd(vInput) else {
            throw NSError(domain: "Ownscribe", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot add video input"])
        }
        w.add(vInput)
        self.writer = w
        self.input = vInput

        let s = SCStream(filter: filter, configuration: config, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.stream = s
        try await s.startCapture()
    }

    /// Stop capture and finalize the file. Returns the written URL if valid.
    func stop() async -> URL? {
        guard let stream else { return nil }
        try? await stream.stopCapture()
        self.stream = nil

        input?.markAsFinished()
        if let writer, writer.status == .writing {
            await writer.finishWriting()
        }
        let url = outputURL
        self.writer = nil
        self.input = nil
        guard let url, FileManager.default.fileExists(atPath: url.path),
              (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0 > 1024
        else { return nil }
        return url
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let writer, let input else { return }

        // Only write frames marked complete by ScreenCaptureKit.
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw),
              status == .complete else { return }

        if writer.status == .unknown {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startWriting()
            writer.startSession(atSourceTime: pts)
            startedSession = true
        }
        guard writer.status == .writing, startedSession, input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        failure = error.localizedDescription
    }
}
