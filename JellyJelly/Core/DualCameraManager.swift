import AVFoundation
import UIKit
import Photos
import SwiftUI
import Combine
import os.log

class DualCameraManager: NSObject, ObservableObject {
    // MARK: - Properties
    
    // Logger for debugging
    private let logger = Logger(subsystem: "com.jellyjelly.app", category: "Camera")
    
    // For devices that support multicam (iOS 13+, A12 chip or later)
    private var multiCamSession: AVCaptureMultiCamSession?
    
    // Camera sessions
    var captureSession: AVCaptureSession? // Make optional to prevent force unwrapping
    
    // Preview layers for multicam setup
    @Published var frontPreviewLayer: AVCaptureVideoPreviewLayer?
    @Published var backPreviewLayer: AVCaptureVideoPreviewLayer?
    
    // Inputs for multicam setup
    private var frontCameraInput: AVCaptureDeviceInput?
    private var backCameraInput: AVCaptureDeviceInput?
    
    // Outputs for multicam setup
    private var frontCameraOutput: AVCaptureMovieFileOutput?
    private var backCameraOutput: AVCaptureMovieFileOutput?
    
    // Devices
    private var frontCamera: AVCaptureDevice?
    private var backCamera: AVCaptureDevice?
    
    // Status tracking
    private var activeCamera: AVCaptureDevice.Position = .back
    
    // Public properties
    var activePosition: AVCaptureDevice.Position {
        return activeCamera
    }
    
    // Published properties
    @Published var isSetupComplete = false
    @Published var setupError: String?
    @Published var isRecording = false
    @Published var recordingInProgress: Bool = false // Alias for isRecording
    @Published var recordingProgress: Double = 0.0
    
    // Error handling
    @Published var recordingError: String?
    @Published var showRecordingError: Bool = false
    
    // Device status
    @Published var cameraAuthorized = false
    @Published var microphoneAuthorized = false
    @Published var showPermissionAlert = false
    
    // Recording options
    @Published var recordingTime: RecordingTime = .fifteenSeconds
    enum RecordingTime: TimeInterval, CaseIterable, Identifiable {
        case fifteenSeconds = 15.0
        case sixtySeconds = 60.0
        
        var id: Self { self }
        
        var displayName: String {
            switch self {
            case .fifteenSeconds: return "15s"
            case .sixtySeconds: return "60s"
            }
        }
    }
    
    // Recording URLs
    private var frontCameraURL: URL?
    private var backCameraURL: URL?
    private var activeRecordingCount = 0
    
    // Timer for tracking recording progress
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    
    private var recordingCompletion: ((Result<URL, Error>) -> Void)?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        print("DualCameraManager initializing...")
        setupCamera()
    }
    
    // MARK: - Camera Setup
    
    private func setupCamera() {
        logger.info("Starting camera setup")
        
        // Check permissions first
        checkPermissions { [weak self] authorized in
            guard let self = self else { 
                self?.logger.error("Self was deallocated during camera setup")
                return 
            }
            
            if !authorized {
                self.logger.error("Camera permissions not granted")
                return
            }
            
            // Only setup multi-camera mode - no fallback
            if #available(iOS 13.0, *), AVCaptureMultiCamSession.isMultiCamSupported {
                self.logger.info("Setting up multi-camera mode")
                print("Setting up multi-camera mode")
                self.setupMultiCameraMode()
            } else {
                self.logger.error("Device does not support multi-camera mode")
                print("Device does not support multi-camera mode")
                // No fallback to single camera mode
            }
            
            // Log camera session status
            DispatchQueue.main.async {
                self.isSetupComplete = true
                self.logger.info("Camera setup complete. Sessions: captureSession=\(self.captureSession != nil ? "initialized" : "nil")")
                print("Camera setup complete: captureSession=\(self.captureSession != nil ? "initialized" : "nil")")
            }
        }
    }
    
    // Check camera and microphone permissions
    private func checkPermissions(completion: @escaping (Bool) -> Void) {
        let cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let audioAuthStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        
        var cameraAuthorized = false
        var micAuthorized = false
        
        let dispatchGroup = DispatchGroup()
        
        // Check camera permission
        if cameraAuthStatus != .authorized {
            dispatchGroup.enter()
            AVCaptureDevice.requestAccess(for: .video) { authorized in
                cameraAuthorized = authorized
                DispatchQueue.main.async {
                    self.cameraAuthorized = authorized
                    if !authorized {
                        self.showPermissionAlert = true
                    }
                }
                dispatchGroup.leave()
            }
        } else {
            cameraAuthorized = true
            DispatchQueue.main.async {
                self.cameraAuthorized = true
            }
        }
        
        // Check microphone permission
        if audioAuthStatus != .authorized {
            dispatchGroup.enter()
            AVCaptureDevice.requestAccess(for: .audio) { authorized in
                micAuthorized = authorized
                DispatchQueue.main.async {
                    self.microphoneAuthorized = authorized
                    if !authorized {
                        self.showPermissionAlert = true
                    }
                }
                dispatchGroup.leave()
            }
        } else {
            micAuthorized = true
            DispatchQueue.main.async {
                self.microphoneAuthorized = true
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            completion(cameraAuthorized && micAuthorized)
        }
    }
    
    // Setup for devices that support multi-camera (iOS 13+ and A12+ chips)
    @available(iOS 13.0, *)
    private func setupMultiCameraMode() {
        // Discover devices
        if let frontDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            self.frontCamera = frontDevice
            self.logger.info("Found front camera: \(frontDevice.localizedName)")
            print("Found front camera: \(frontDevice.localizedName)")
        } else {
            self.logger.error("No front camera device found")
        }
        
        if let backDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            self.backCamera = backDevice
            self.logger.info("Found back camera: \(backDevice.localizedName)")
            print("Found back camera: \(backDevice.localizedName)")
        } else {
            self.logger.error("No back camera device found")
        }
        
        // Check if device supports multi-camera
        if !AVCaptureMultiCamSession.isMultiCamSupported {
            self.logger.error("Multi-camera setup is not supported on this device")
            return
        }
        
        self.logger.info("Multi-camera setup is supported on this device")
        print("Multi-camera setup is supported on this device")
        
        // Create multi-camera session
        let session = AVCaptureMultiCamSession()
        self.multiCamSession = session
        self.captureSession = session
        
        // Start session configuration
        session.beginConfiguration()
        
        // Configure front camera input
        guard let frontDevice = self.frontCamera,
              let backDevice = self.backCamera else {
            self.logger.error("Camera devices not available")
            return
        }
        
        do {
            // Configure devices for optimal recording settings
            try self.configureCameraDeviceForRecording(device: frontDevice)
            try self.configureCameraDeviceForRecording(device: backDevice)
            
            let frontInput = try AVCaptureDeviceInput(device: frontDevice)
            if session.canAddInput(frontInput) {
                session.addInput(frontInput)
                self.frontCameraInput = frontInput
                self.logger.info("Front camera configured for multicam")
                print("Front camera configured for multicam")
            } else {
                self.logger.error("Cannot add front camera to multicam session")
                session.commitConfiguration()
                return
            }
            
            // Configure back camera input
            let backInput = try AVCaptureDeviceInput(device: backDevice)
            if session.canAddInput(backInput) {
                session.addInput(backInput)
                self.backCameraInput = backInput
                self.logger.info("Back camera configured for multicam")
                print("Back camera configured for multicam")
            } else {
                self.logger.error("Cannot add back camera to multicam session")
                session.commitConfiguration()
                return
            }
            
            // Configure audio input
            if let audioDevice = AVCaptureDevice.default(for: .audio) {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                    self.logger.info("Audio added to multicam session")
                    print("Audio added to multicam session")
                }
                
                // Configure movie file outputs for recording
                let frontOutput = AVCaptureMovieFileOutput()
                let backOutput = AVCaptureMovieFileOutput()
                
                // Set movie fragment interval for better recording
                frontOutput.movieFragmentInterval = .invalid
                backOutput.movieFragmentInterval = .invalid
                
                if session.canAddOutput(frontOutput) && session.canAddOutput(backOutput) {
                    session.addOutput(frontOutput)
                    session.addOutput(backOutput)
                    
                    self.frontCameraOutput = frontOutput
                    self.backCameraOutput = backOutput
                    
                    // Connect front camera
                    if let videoPort = frontInput.ports(for: .video, sourceDeviceType: frontDevice.deviceType, sourceDevicePosition: .front).first,
                       let audioPort = audioInput.ports(for: .audio, sourceDeviceType: audioDevice.deviceType, sourceDevicePosition: .unspecified).first {
                        
                        let frontVideoConnection = AVCaptureConnection(inputPorts: [videoPort], output: frontOutput)
                        let frontAudioConnection = AVCaptureConnection(inputPorts: [audioPort], output: frontOutput)
                        
                        // Configure front camera connection
                        if session.canAddConnection(frontVideoConnection) && session.canAddConnection(frontAudioConnection) {
                            // Set orientation based on what's supported
                            if frontVideoConnection.isVideoRotationAngleSupported(.pi/2) {
                                frontVideoConnection.videoRotationAngle = .pi/2 // 90 degrees (portrait)
                            } else {
                                // Fall back to deprecated API with warning
                                #if DEBUG
                                print("Warning: videoRotationAngle not supported, falling back to videoOrientation")
                                #endif
                                frontVideoConnection.videoOrientation = .portrait
                            }
                            
                            frontVideoConnection.automaticallyAdjustsVideoMirroring = false
                            frontVideoConnection.isVideoMirrored = true
                            
                            session.addConnection(frontVideoConnection)
                            session.addConnection(frontAudioConnection)
                            self.logger.info("Front camera connections configured")
                            print("Front camera connections configured")
                        } else {
                            self.logger.error("Could not add front camera connections")
                        }
                    }
                    
                    // Connect back camera
                    if let videoPort = backInput.ports(for: .video, sourceDeviceType: backDevice.deviceType, sourceDevicePosition: .back).first,
                       let audioPort = audioInput.ports(for: .audio, sourceDeviceType: audioDevice.deviceType, sourceDevicePosition: .unspecified).first {
                        
                        let backVideoConnection = AVCaptureConnection(inputPorts: [videoPort], output: backOutput)
                        let backAudioConnection = AVCaptureConnection(inputPorts: [audioPort], output: backOutput)
                        
                        // Configure back camera connection
                        if session.canAddConnection(backVideoConnection) && session.canAddConnection(backAudioConnection) {
                            // Set orientation based on what's supported
                            if backVideoConnection.isVideoRotationAngleSupported(.pi/2) {
                                backVideoConnection.videoRotationAngle = .pi/2 // 90 degrees (portrait)
                            } else {
                                // Fall back to deprecated API with warning
                                #if DEBUG
                                print("Warning: videoRotationAngle not supported, falling back to videoOrientation")
                                #endif
                                backVideoConnection.videoOrientation = .portrait
                            }
                            
                            session.addConnection(backVideoConnection)
                            session.addConnection(backAudioConnection)
                            self.logger.info("Back camera connections configured")
                            print("Back camera connections configured")
                        } else {
                            self.logger.error("Could not add back camera connections")
                        }
                    }
                    
                } else {
                    self.logger.error("Cannot add movie outputs to multicam session")
                }
            }
            
        } catch {
            self.logger.error("Error setting up multicam: \(error.localizedDescription)")
            print("Error setting up multicam: \(error.localizedDescription)")
            session.commitConfiguration()
            return
        }
        
        // Commit configuration
        session.commitConfiguration()
        
        // Debug - print status before session starts
        self.debugCameraStatus()
        
        // Start the session on a background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            print("Starting camera session...")
            self.multiCamSession?.startRunning()
            print("Camera session running: \(self.multiCamSession?.isRunning == true ? "yes" : "no")")
            
            // Only create and setup preview layers after session is running
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let session = self.multiCamSession else { return }
                
                // Use a simpler approach - create layers that just display the session content
                // The UI will place them in the correct positions
                let frontLayer = AVCaptureVideoPreviewLayer(session: session)
                let backLayer = AVCaptureVideoPreviewLayer(session: session)
                
                // Set video gravity
                frontLayer.videoGravity = .resizeAspectFill
                backLayer.videoGravity = .resizeAspectFill
                
                // Set properties for both layers
                if let connection = frontLayer.connection {
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = true
                }
                
                if let connection = backLayer.connection {
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }
                }
                
                // Store the layers for UI access
                self.frontPreviewLayer = frontLayer
                self.backPreviewLayer = backLayer
                
                print("Preview layers created and assigned")
                self.debugCameraStatus()
            }
        }
    }
    
    // Configure camera device for optimal recording
    private func configureCameraDeviceForRecording(device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        
        // Set frame rate
        if device.activeFormat.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 0 > 30 {
            // Use 30fps for most compatible recording
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        }
        
        // Set focus mode
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        
        // Set exposure mode
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        
        // Set white balance mode
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        
        device.unlockForConfiguration()
    }
    
    // MARK: - Recording Methods
    
    // Prepare for recording
    func prepareForRecording() {
        print("Preparing for recording")
        // Additional setup if needed before recording
    }
    
    // Start recording
    func startRecording() {
        guard !self.isRecording else {
            self.logger.error("Recording already in progress")
            print("Recording already in progress")
            return
        }
        
        print("Starting recording")
        
        // Make sure we have proper camera setup
        guard let frontOutput = self.frontCameraOutput,
              let backOutput = self.backCameraOutput,
              let session = self.multiCamSession,
              session.isRunning else {
            self.logger.error("Cannot start recording - camera not properly set up")
            print("Cannot start recording - camera not properly set up")
            self.showRecordingError = true
            self.recordingError = "Camera is not ready. Please restart the app."
            return
        }
        
        // Check permission to write to photo library
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            guard let self = self else { return }
            
            if status != .authorized {
                DispatchQueue.main.async {
                    self.showRecordingError = true
                    self.recordingError = "Please allow access to your photo library to save videos."
                }
                return
            }
            
            DispatchQueue.main.async {
                // Set recording status
                self.isRecording = true
                self.recordingInProgress = true
                
                // Get temporary file URLs for front and back camera recordings
                let frontURL = self.getTemporaryFileURL(prefix: "front_camera")
                let backURL = self.getTemporaryFileURL(prefix: "back_camera")
                
                // Start recording timer
                self.startRecordingTimer()
                
                // Start recording with both cameras
                print("Starting front camera recording to: \(frontURL.path)")
                frontOutput.startRecording(to: frontURL, recordingDelegate: self)
                
                print("Starting back camera recording to: \(backURL.path)")
                backOutput.startRecording(to: backURL, recordingDelegate: self)
            }
        }
    }
    
    // Stop recording
    func stopRecording() {
        guard self.isRecording else {
            self.logger.error("No recording in progress")
            print("No recording in progress")
            return
        }
        
        print("Stopping recording")
        
        // Stop the recording timer
        self.recordingTimer?.invalidate()
        self.recordingTimer = nil
        
        // Stop recordings for both cameras
        self.frontCameraOutput?.stopRecording()
        self.backCameraOutput?.stopRecording()
        
        // Reset recording status
        DispatchQueue.main.async {
            self.isRecording = false
            self.recordingInProgress = false
            self.recordingProgress = 0.0
        }
    }
    
    // Save recording to photo library
    private func saveRecordingToPhotoLibrary(fileURL: URL, isFrontCamera: Bool) {
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            guard let self = self else { return }
            
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    // Create a new video asset in the photo library
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
                }) { success, error in
                    if success {
                        let cameraPosition = isFrontCamera ? "front" : "back"
                        print("Video saved to photo library: \(cameraPosition) camera")
                        
                        // Post notification that video was recorded
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: .videoRecorded, object: nil)
                        }
                    } else if let error = error {
                        print("Error saving video to photo library: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            self.showRecordingError = true
                            self.recordingError = "Error saving video: \(error.localizedDescription)"
                        }
                    }
                }
            } else {
                print("Photo library access not authorized")
                DispatchQueue.main.async {
                    self.showRecordingError = true
                    self.recordingError = "Photo library access not authorized. Please enable in Settings."
                }
            }
        }
    }
    
    // MARK: - Timer Methods
    
    private func startRecordingTimer() {
        self.recordingStartTime = Date()
        
        // Create a timer to update recording progress
        self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self,
                  let startTime = self.recordingStartTime else { return }
            
            let elapsedTime = Date().timeInterval(since: startTime)
            let duration = self.recordingTime.rawValue
            let progress = min(elapsedTime / duration, 1.0)
            
            DispatchQueue.main.async {
                self.recordingProgress = progress
            }
            
            // Automatically stop recording when time is up
            if elapsedTime >= duration {
                self.stopRecording()
            }
        }
    }
    
    private func stopRecordingTimer() {
        self.recordingTimer?.invalidate()
        self.recordingTimer = nil
        self.recordingStartTime = nil
    }
    
    // MARK: - Cleanup Methods
    
    func cleanup() {
        // Stop any ongoing recording
        if self.isRecording {
            self.stopRecording()
        }
        
        // Stop session
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.multiCamSession?.stopRunning()
        }
    }
    
    // Add debug method to print camera status
    private func debugCameraStatus() {
        self.logger.info("DualCameraManager Status:")
        self.logger.info("MultiCamSession: \(self.multiCamSession != nil ? "initialized" : "nil")")
        self.logger.info("MultiCamSession running: \(self.multiCamSession?.isRunning == true ? "yes" : "no")")
        self.logger.info("FrontCamera: \(self.frontCamera != nil ? "initialized" : "nil")")
        self.logger.info("BackCamera: \(self.backCamera != nil ? "initialized" : "nil")")
        self.logger.info("FrontCameraInput: \(self.frontCameraInput != nil ? "initialized" : "nil")")
        self.logger.info("BackCameraInput: \(self.backCameraInput != nil ? "initialized" : "nil")")
        self.logger.info("FrontCameraOutput: \(self.frontCameraOutput != nil ? "initialized" : "nil")")
        self.logger.info("BackCameraOutput: \(self.backCameraOutput != nil ? "initialized" : "nil")")
        self.logger.info("FrontPreviewLayer: \(self.frontPreviewLayer != nil ? "initialized" : "nil")")
        self.logger.info("BackPreviewLayer: \(self.backPreviewLayer != nil ? "initialized" : "nil")")
        
        // Print to console for easier debugging during development
        print("---- DualCameraManager Status ----")
        print("MultiCamSession: \(self.multiCamSession != nil ? "initialized" : "nil")")
        print("MultiCamSession running: \(self.multiCamSession?.isRunning == true ? "yes" : "no")")
        print("FrontCamera: \(self.frontCamera != nil ? "initialized" : "nil")")
        print("BackCamera: \(self.backCamera != nil ? "initialized" : "nil")")
        print("FrontCameraInput: \(self.frontCameraInput != nil ? "initialized" : "nil")")
        print("BackCameraInput: \(self.backCameraInput != nil ? "initialized" : "nil")")
        print("FrontCameraOutput: \(self.frontCameraOutput != nil ? "initialized" : "nil")")
        print("BackCameraOutput: \(self.backCameraOutput != nil ? "initialized" : "nil")")
        print("FrontPreviewLayer: \(self.frontPreviewLayer != nil ? "initialized" : "nil")")
        print("BackPreviewLayer: \(self.backPreviewLayer != nil ? "initialized" : "nil")")
        print("-------------------------------")
    }
    
    // Get a temporary file URL for recording
    private func getTemporaryFileURL(prefix: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = Date().timeIntervalSince1970
        return tempDir.appendingPathComponent("\(prefix)_\(timestamp).mov")
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
extension DualCameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        self.logger.info("Recording started to: \(fileURL.path)")
        print("Recording started to: \(fileURL.path)")
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        // Handle any recording errors
        if let error = error {
            self.logger.error("Recording error: \(error.localizedDescription)")
            print("Recording error: \(error.localizedDescription)")
            self.handleRecordingError("Recording failed: \(error.localizedDescription)")
            return
        }
        
        print("Successfully recorded to: \(outputFileURL.path)")
        
        // Save both front and back camera recordings to photo library
        if output == self.frontCameraOutput {
            self.saveRecordingToPhotoLibrary(fileURL: outputFileURL, isFrontCamera: true)
        } else if output == self.backCameraOutput {
            self.saveRecordingToPhotoLibrary(fileURL: outputFileURL, isFrontCamera: false)
        }
    }
    
    // Handle recording errors
    private func handleRecordingError(_ message: String) {
        DispatchQueue.main.async {
            self.recordingError = message
            self.showRecordingError = true
            self.isRecording = false
            self.recordingInProgress = false
            self.recordingProgress = 0.0
            self.stopRecordingTimer()
        }
    }
}

// MARK: - Error Handling
extension DualCameraManager {
    enum CameraError: Error, LocalizedError {
        case cameraNotSetup
        case frontCameraUnavailable
        case backCameraUnavailable
        case permissionDenied
        case outputNotConfigured
        case alreadyRecording
        case notRecording
        case cannotSwitchWhileRecording
        
        var errorDescription: String? {
            switch self {
            case .cameraNotSetup:
                return "Camera not set up properly"
            case .frontCameraUnavailable:
                return "Front camera is not available"
            case .backCameraUnavailable:
                return "Back camera is not available"
            case .permissionDenied:
                return "Camera or microphone permission is denied"
            case .outputNotConfigured:
                return "Camera output is not configured properly"
            case .alreadyRecording:
                return "Already recording"
            case .notRecording:
                return "Not recording"
            case .cannotSwitchWhileRecording:
                return "Cannot switch camera while recording"
            }
        }
    }
}

// MARK: - Date Extension
extension Date {
    func timeInterval(since date: Date) -> TimeInterval {
        return self.timeIntervalSince1970 - date.timeIntervalSince1970
    }
} 