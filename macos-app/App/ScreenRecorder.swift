//
//  ScreenRecorder.swift
//  macos-app
//

import AppKit
@preconcurrency import AVFoundation
import Combine
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit

@MainActor
final class ScreenRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lastOutputURL: URL?

    private var session: DisplayRecordingSession?

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        lastErrorMessage = nil

        if !CGPreflightScreenCaptureAccess() {
            let didRequest = CGRequestScreenCaptureAccess()
            if !didRequest || !CGPreflightScreenCaptureAccess() {
                lastErrorMessage = "Screen recording permission is not available."
                showAlert(
                    message: "Screen Recording Permission Needed",
                    detail: "Enable wkdomains in System Settings > Privacy & Security > Screen Recording, then try again."
                )
                return
            }
        }

        Task {
            do {
                let outputURL = Self.desktopOutputURL()
                let session = try await DisplayRecordingSession(outputURL: outputURL)
                try await session.start { [weak self] result in
                    Task { @MainActor in
                        self?.handleFinish(result)
                    }
                }

                self.session = session
                self.lastOutputURL = outputURL
                self.isRecording = true
            } catch {
                self.lastErrorMessage = error.localizedDescription
                self.showAlert(message: "Could Not Start Recording", detail: error.localizedDescription)
            }
        }
    }

    func stopRecording() {
        guard let session else { return }
        isRecording = false
        self.session = nil
        Task {
            await session.stop()
        }
    }

    private func handleFinish(_ result: Result<URL, Error>) {
        isRecording = false
        session = nil

        switch result {
        case .success(let outputURL):
            lastOutputURL = outputURL
        case .failure(let error):
            lastErrorMessage = error.localizedDescription
            showAlert(message: "Recording Failed", detail: error.localizedDescription)
        }
    }

    private func showAlert(message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.runModal()
    }

    private static func desktopOutputURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "wkdomain_\(formatter.string(from: Date())).mov"
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent(filename)
    }
}

private final class DisplayRecordingSession: NSObject, SCStreamDelegate, SCStreamOutput, @unchecked Sendable {
    private enum RecordingError: LocalizedError {
        case couldNotFindDisplay
        case couldNotAddVideoInput
        case writerFailed(String)
        case noFramesWritten

        var errorDescription: String? {
            switch self {
            case .couldNotFindDisplay:
                return "No capturable display was found."
            case .couldNotAddVideoInput:
                return "The movie writer could not add a video input."
            case .writerFailed(let message):
                return message
            case .noFramesWritten:
                return "The recording stopped before any video frames were captured."
            }
        }
    }

    private let outputURL: URL
    private let display: SCDisplay
    private let configuration: SCStreamConfiguration
    private let queue = DispatchQueue(label: "com.wkdomains.screen-recorder")
    nonisolated(unsafe) private let writer: AVAssetWriter
    nonisolated(unsafe) private let videoInput: AVAssetWriterInput
    nonisolated(unsafe) private let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor

    nonisolated(unsafe) private var stream: SCStream?
    nonisolated(unsafe) private var finishHandler: ((Result<URL, Error>) -> Void)?
    nonisolated(unsafe) private var firstPresentationTime: CMTime?
    nonisolated(unsafe) private var didStartSession = false
    nonisolated(unsafe) private var didAppendFrame = false
    nonisolated(unsafe) private var isStopping = false
    nonisolated(unsafe) private var didFinish = false

    init(outputURL: URL) async throws {
        self.outputURL = outputURL

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let mainDisplayID = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == mainDisplayID }) ?? content.displays.first else {
            throw RecordingError.couldNotFindDisplay
        }
        self.display = display

        let nativeWidth = CGFloat(display.width)
        let nativeHeight = CGFloat(display.height)
        let scale = min(1, 1920 / max(nativeWidth, 1))
        let width = max(2, Int((nativeWidth * scale).rounded(.down))) & ~1
        let height = max(2, Int((nativeHeight * scale).rounded(.down))) & ~1

        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 5
        configuration.showsCursor = true
        configuration.capturesAudio = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        self.configuration = configuration

        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        let sourceAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: sourceAttributes
        )

        guard writer.canAdd(videoInput) else {
            throw RecordingError.couldNotAddVideoInput
        }
        writer.add(videoInput)
    }

    func start(finishHandler: @escaping (Result<URL, Error>) -> Void) async throws {
        self.finishHandler = finishHandler

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        self.stream = stream

        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
    }

    func stop() async {
        let stream = stream
        try? await stream?.stopCapture()

        queue.async { [weak self] in
            guard let self, !self.isStopping else { return }
            self.isStopping = true
            self.stream = nil
            self.finish()
        }
    }

    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen else { return }
        appendScreenSampleBuffer(sampleBuffer)
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        finishWithFailure(error)
    }

    nonisolated private func appendScreenSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard !isStopping, sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard isCompleteFrame(sampleBuffer) else { return }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        guard writer.status != .failed else {
            finishWithFailure(writer.error ?? RecordingError.writerFailed("The movie writer failed."))
            return
        }

        if !didStartSession {
            guard writer.startWriting() else {
                finishWithFailure(writer.error ?? RecordingError.writerFailed("The movie writer could not start."))
                return
            }
            writer.startSession(atSourceTime: .zero)
            firstPresentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            didStartSession = true
        }

        guard videoInput.isReadyForMoreMediaData else { return }
        let presentationTime = normalizedPresentationTime(for: sampleBuffer)

        guard pixelBufferAdaptor.append(imageBuffer, withPresentationTime: presentationTime) else {
            finishWithFailure(writer.error ?? RecordingError.writerFailed("A captured video frame could not be written."))
            return
        }

        didAppendFrame = true
    }

    nonisolated private func normalizedPresentationTime(for sampleBuffer: CMSampleBuffer) -> CMTime {
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard let firstPresentationTime else { return .zero }
        let relativeTime = CMTimeSubtract(presentationTime, firstPresentationTime)
        return relativeTime >= .zero ? relativeTime : .zero
    }

    nonisolated private func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
            let rawStatus = attachments.first?[.status] as? Int,
            let status = SCFrameStatus(rawValue: rawStatus)
        else {
            return true
        }

        return status == .complete
    }

    nonisolated private func finish() {
        guard !didFinish else { return }
        didFinish = true

        guard didAppendFrame else {
            videoInput.markAsFinished()
            writer.cancelWriting()
            finishHandler?(.failure(RecordingError.noFramesWritten))
            finishHandler = nil
            return
        }

        videoInput.markAsFinished()
        writer.finishWriting { [outputURL, writer, finishHandler] in
            if writer.status == .completed {
                finishHandler?(.success(outputURL))
            } else {
                let error = writer.error ?? RecordingError.writerFailed("The movie writer did not finish successfully.")
                finishHandler?(.failure(error))
            }
        }
        finishHandler = nil
    }

    nonisolated private func finishWithFailure(_ error: Error) {
        guard !didFinish else { return }
        didFinish = true
        videoInput.markAsFinished()
        writer.cancelWriting()
        finishHandler?(.failure(error))
        finishHandler = nil
    }
}
