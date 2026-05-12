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
    @Published private(set) var isPaused = false
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
        guard !isRecording, session == nil else { return }
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
        isPaused = false
        Task {
            await session.stop()
        }
    }

    func togglePause() {
        if isPaused {
            resumeRecording()
        } else {
            pauseRecording()
        }
    }

    func pauseRecording() {
        guard let session, isRecording else { return }
        guard !isPaused else { return }

        isPaused = true
        Task {
            do {
                try await session.pause()
            } catch {
                self.handleFinish(.failure(error))
            }
        }
    }

    func resumeRecording() {
        guard let session, isRecording else { return }
        guard isPaused else { return }

        Task {
            do {
                try await session.resume()
                self.isPaused = false
            } catch {
                self.handleFinish(.failure(error))
            }
        }
    }

    var apiState: [String: Any] {
        [
            "recording": isRecording,
            "paused": isPaused,
            "outputPath": lastOutputURL?.path ?? NSNull(),
            "lastError": lastErrorMessage ?? NSNull()
        ]
    }

    private func handleFinish(_ result: Result<URL, Error>) {
        isRecording = false
        isPaused = false
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

private final class DisplayRecordingSession: NSObject, SCStreamDelegate, SCRecordingOutputDelegate, @unchecked Sendable {
    private enum RecordingError: LocalizedError {
        case couldNotFindDisplay
        case couldNotAddRecordingOutput
        case noSegmentsRecorded
        case recordingFailed(String)
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .couldNotFindDisplay:
                return "No capturable display was found."
            case .couldNotAddRecordingOutput:
                return "The screen recording output could not be added."
            case .noSegmentsRecorded:
                return "The recording stopped before any video was captured."
            case .recordingFailed(let message):
                return message
            case .exportFailed:
                return "The paused recording segments could not be joined."
            }
        }
    }

    private let outputURL: URL
    private let display: SCDisplay
    private let configuration: SCStreamConfiguration
    private let temporaryDirectoryURL: URL
    nonisolated(unsafe) private var stream: SCStream?
    nonisolated(unsafe) private var recordingOutput: SCRecordingOutput?
    nonisolated(unsafe) private var finishHandler: ((Result<URL, Error>) -> Void)?
    nonisolated(unsafe) private var segmentURLs: [URL] = []
    nonisolated(unsafe) private var activeSegmentURL: URL?
    nonisolated(unsafe) private var segmentFinishContinuation: CheckedContinuation<URL, Error>?
    nonisolated(unsafe) private var isPaused = false
    nonisolated(unsafe) private var isStopping = false
    nonisolated(unsafe) private var didFinish = false

    init(outputURL: URL) async throws {
        self.outputURL = outputURL
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("wkdomains-recording-\(UUID().uuidString)", isDirectory: true)

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let mainDisplayID = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == mainDisplayID }) ?? content.displays.first else {
            throw RecordingError.couldNotFindDisplay
        }
        self.display = display

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let width = max(2, Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded())) & ~1
        let height = max(2, Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded())) & ~1

        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 8
        configuration.showsCursor = true
        configuration.capturesAudio = false
        configuration.captureMicrophone = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.captureResolution = .best
        self.configuration = configuration

        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: temporaryDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    func start(finishHandler: @escaping (Result<URL, Error>) -> Void) async throws {
        self.finishHandler = finishHandler
        try await startSegment()
    }

    func pause() async throws {
        guard !isPaused, !isStopping else { return }
        isPaused = true
        _ = try await stopActiveSegment()
    }

    func resume() async throws {
        guard isPaused, !isStopping else { return }
        isPaused = false
        try await startSegment()
    }

    func stop() async {
        guard !isStopping else { return }
        isStopping = true

        do {
            if stream != nil {
                _ = try await stopActiveSegment()
            }
            try await writeFinalMovie()
            cleanupTemporarySegments()
            finishWithSuccess()
        } catch {
            cleanupTemporarySegments()
            finishWithFailure(error)
        }
    }

    private func startSegment() async throws {
        let segmentURL = temporaryDirectoryURL
            .appendingPathComponent("segment-\(segmentURLs.count + 1).mov")
        try? FileManager.default.removeItem(at: segmentURL)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = segmentURL
        recordingConfiguration.outputFileType = .mov
        recordingConfiguration.videoCodecType = .h264

        let recordingOutput = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)
        do {
            try stream.addRecordingOutput(recordingOutput)
        } catch {
            throw RecordingError.couldNotAddRecordingOutput
        }

        self.stream = stream
        self.recordingOutput = recordingOutput
        activeSegmentURL = segmentURL
        try await stream.startCapture()
    }

    private func stopActiveSegment() async throws -> URL? {
        guard let stream, activeSegmentURL != nil else { return nil }

        return try await withCheckedThrowingContinuation { continuation in
            segmentFinishContinuation = continuation
            Task {
                do {
                    try await stream.stopCapture()
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    if self.segmentFinishContinuation != nil, self.activeSegmentURL != nil {
                        self.finishActiveSegment()
                    }
                } catch {
                    finishActiveSegmentAfterStop(error)
                }
            }
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        finishActiveSegment()
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        if segmentFinishContinuation != nil {
            finishActiveSegmentAfterStop(error)
        } else if !isStopping {
            finishWithFailure(error)
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        if segmentFinishContinuation != nil {
            finishActiveSegmentAfterStop(error)
        } else if !isStopping {
            finishWithFailure(error)
        }
    }

    nonisolated private func finishWithSuccess() {
        guard !didFinish else { return }
        didFinish = true
        let outputURL = outputURL
        recordingOutput = nil
        finishHandler?(.success(outputURL))
        finishHandler = nil
    }

    nonisolated private func finishWithFailure(_ error: Error) {
        guard !didFinish else { return }
        didFinish = true
        recordingOutput = nil
        finishHandler?(.failure(RecordingError.recordingFailed(error.localizedDescription)))
        finishHandler = nil
    }

    nonisolated private func finishActiveSegment() {
        guard let activeSegmentURL else { return }
        stream = nil
        recordingOutput = nil
        self.activeSegmentURL = nil

        if FileManager.default.fileExists(atPath: activeSegmentURL.path),
           fileSize(at: activeSegmentURL) > 0 {
            segmentURLs.append(activeSegmentURL)
            segmentFinishContinuation?.resume(returning: activeSegmentURL)
        } else {
            segmentFinishContinuation?.resume(throwing: RecordingError.noSegmentsRecorded)
        }
        segmentFinishContinuation = nil
    }

    nonisolated private func finishActiveSegmentAfterStop(_ error: Error) {
        guard let activeSegmentURL else {
            segmentFinishContinuation?.resume(throwing: error)
            segmentFinishContinuation = nil
            return
        }

        if FileManager.default.fileExists(atPath: activeSegmentURL.path),
           fileSize(at: activeSegmentURL) > 0 {
            finishActiveSegment()
        } else {
            stream = nil
            recordingOutput = nil
            self.activeSegmentURL = nil
            segmentFinishContinuation?.resume(throwing: error)
            segmentFinishContinuation = nil
        }
    }

    private func writeFinalMovie() async throws {
        let usableSegmentURLs = segmentURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard let firstSegmentURL = usableSegmentURLs.first else {
            throw RecordingError.noSegmentsRecorded
        }

        try? FileManager.default.removeItem(at: outputURL)

        if usableSegmentURLs.count == 1 {
            try FileManager.default.copyItem(at: firstSegmentURL, to: outputURL)
            return
        }

        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw RecordingError.exportFailed
        }

        var insertionTime = CMTime.zero
        var appliedPreferredTransform = false

        for segmentURL in usableSegmentURLs {
            let asset = AVURLAsset(url: segmentURL)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let videoTrack = videoTracks.first else { continue }

            let duration = try await asset.load(.duration)
            guard duration > .zero else { continue }

            if !appliedPreferredTransform {
                compositionTrack.preferredTransform = try await videoTrack.load(.preferredTransform)
                appliedPreferredTransform = true
            }

            try compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: videoTrack,
                at: insertionTime
            )
            insertionTime = CMTimeAdd(insertionTime, duration)
        }

        guard insertionTime > .zero else {
            throw RecordingError.noSegmentsRecorded
        }

        try await export(composition)
    }

    private func export(_ composition: AVMutableComposition) async throws {
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) ?? AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw RecordingError.exportFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.shouldOptimizeForNetworkUse = false

        try await withCheckedThrowingContinuation { continuation in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume(returning: ())
                case .failed, .cancelled:
                    continuation.resume(throwing: exportSession.error ?? RecordingError.exportFailed)
                default:
                    continuation.resume(throwing: RecordingError.exportFailed)
                }
            }
        }
    }

    nonisolated private func fileSize(at url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func cleanupTemporarySegments() {
        try? FileManager.default.removeItem(at: temporaryDirectoryURL)
    }
}
