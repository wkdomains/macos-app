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
        let filename = "wkdomain_\(formatter.string(from: Date())).mp4"
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent(filename)
    }
}

private final class DisplayRecordingSession: NSObject, SCStreamDelegate, SCRecordingOutputDelegate, @unchecked Sendable {
    private enum RecordingError: LocalizedError {
        case couldNotFindDisplay
        case couldNotAddRecordingOutput
        case recordingFailed(String)

        var errorDescription: String? {
            switch self {
            case .couldNotFindDisplay:
                return "No capturable display was found."
            case .couldNotAddRecordingOutput:
                return "The screen recording output could not be added."
            case .recordingFailed(let message):
                return message
            }
        }
    }

    private let outputURL: URL
    private let display: SCDisplay
    private let configuration: SCStreamConfiguration
    nonisolated(unsafe) private var stream: SCStream?
    nonisolated(unsafe) private var recordingOutput: SCRecordingOutput?
    nonisolated(unsafe) private var finishHandler: ((Result<URL, Error>) -> Void)?
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
        configuration.captureMicrophone = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        self.configuration = configuration

        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    func start(finishHandler: @escaping (Result<URL, Error>) -> Void) async throws {
        self.finishHandler = finishHandler

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = outputURL
        recordingConfiguration.outputFileType = .mp4
        recordingConfiguration.videoCodecType = .h264

        let recordingOutput = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)
        try stream.addRecordingOutput(recordingOutput)

        self.stream = stream
        self.recordingOutput = recordingOutput
        try await stream.startCapture()
    }

    func stop() async {
        guard !isStopping else { return }
        isStopping = true

        if let recordingOutput {
            do {
                try stream?.removeRecordingOutput(recordingOutput)
            } catch {
                finishWithFailure(error)
            }
        }

        try? await stream?.stopCapture()
        self.stream = nil
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        finishWithSuccess()
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        finishWithFailure(error)
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        finishWithFailure(error)
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
}
