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
    var frontCameraPreviewSession: AVCaptureSession?
    var backCameraPreviewSession: AVCaptureSession?
    
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
    
    // Error state
    @Published var recordingError: String?
    @Published var showRecordingError = false
    
    // Timer for tracking recording progress
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    
    private var recordingCompletion: ((Result<URL, Error>) -> Void)?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        print("DualCameraManager initialized")
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
                self.logger.info("Camera setup complete. Sessions: captureSession=\(self.captureSession != nil ? "initialized" : "nil"), frontSession=\(self.frontCameraPreviewSession != nil ? "initialized" : "nil"), backSession=\(self.backCameraPreviewSession != nil ? "initialized" : "nil")")
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
        // Create individual camera sessions for preview
        setupIndividualCameraPreviews()
        
        // Discover devices
        if let frontDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            self.frontCamera = frontDevice
            logger.info("Found front camera: \(frontDevice.localizedName)")
            print("Found front camera: Front Camera")
        } else {
            logger.error("No front camera device found")
        }
        
        if let backDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            self.backCamera = backDevice
            logger.info("Found back camera: \(backDevice.localizedName)")
            print("Found back camera: Back Camera")
        } else {
            logger.error("No back camera device found")
        }
        
        logger.info("Multi-camera setup is supported on this device")
        print("Multi-camera setup is supported on this device")
        
        // Create the multi-camera session for recording
        let session = AVCaptureMultiCamSession()
        
        guard let frontDevice = frontCamera ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let backDevice = backCamera ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let audioDevice = AVCaptureDevice.default(for: .audio) else {
            logger.error("Failed to get required camera devices")
            print("Failed to get required camera devices")
            return
        }
        
        do {
            // Create inputs
            let frontInput = try AVCaptureDeviceInput(device: frontDevice)
            let backInput = try AVCaptureDeviceInput(device: backDevice)
            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
            
            // Store for later use
            self.frontCameraInput = frontInput
            self.backCameraInput = backInput
            
            // Configure session
            if session.canAddInput(frontInput) &&
                session.canAddInput(backInput) &&
                session.canAddInput(audioInput) {
                
                session.beginConfiguration()
                
                // Add inputs
                session.addInputWithNoConnections(frontInput)
                logger.info("Front camera configured for multicam")
                print("Front camera configured for multicam")
                
                session.addInputWithNoConnections(backInput)
                logger.info("Back camera configured for multicam")
                print("Back camera configured for multicam")
                
                session.addInputWithNoConnections(audioInput)
                logger.info("Audio added to multicam session")
                print("Audio added to multicam session")
                
                // Setup front camera output
                let frontOutput = AVCaptureMovieFileOutput()
                if session.canAddOutput(frontOutput) {
                    session.addOutputWithNoConnections(frontOutput)
                    self.frontCameraOutput = frontOutput
                    
                    // Connect front camera
                    if let videoPort = frontInput.ports(for: .video, sourceDeviceType: frontDevice.deviceType, sourceDevicePosition: .front).first,
                       let audioPort = audioInput.ports(for: .audio, sourceDeviceType: audioDevice.deviceType, sourceDevicePosition: .unspecified).first {
                        
                        let frontVideoConnection = AVCaptureConnection(inputPorts: [videoPort], output: frontOutput)
                        let frontAudioConnection = AVCaptureConnection(inputPorts: [audioPort], output: frontOutput)
                        
                        // Configure front camera connection
                        if session.canAddConnection(frontVideoConnection) && session.canAddConnection(frontAudioConnection) {
                            frontVideoConnection.videoOrientation = .portrait
                            frontVideoConnection.automaticallyAdjustsVideoMirroring = false
                            frontVideoConnection.isVideoMirrored = true
                            
                            session.addConnection(frontVideoConnection)
                            session.addConnection(frontAudioConnection)
                            logger.info("Front camera connections configured")
                        } else {
                            logger.error("Could not add front camera connections")
                        }
                    } else {
                        logger.error("Could not find ports for front camera")
                    }
                } else {
                    logger.error("Could not add front camera output")
                }
                
                // Setup back camera output
                let backOutput = AVCaptureMovieFileOutput()
                if session.canAddOutput(backOutput) {
                    session.addOutputWithNoConnections(backOutput)
                    self.backCameraOutput = backOutput
                    
                    // Connect back camera
                    if let videoPort = backInput.ports(for: .video, sourceDeviceType: backDevice.deviceType, sourceDevicePosition: .back).first,
                       let audioPort = audioInput.ports(for: .audio, sourceDeviceType: audioDevice.deviceType, sourceDevicePosition: .unspecified).first {
                        
                        let backVideoConnection = AVCaptureConnection(inputPorts: [videoPort], output: backOutput)
                        let backAudioConnection = AVCaptureConnection(inputPorts: [audioPort], output: backOutput)
                        
                        // Configure back camera connection
                        if session.canAddConnection(backVideoConnection) && session.canAddConnection(backAudioConnection) {
                            backVideoConnection.videoOrientation = .portrait
                            
                            session.addConnection(backVideoConnection)
                            session.addConnection(backAudioConnection)
                            logger.info("Back camera connections configured")
                        } else {
                            logger.error("Could not add back camera connections")
                        }
                    } else {
                        logger.error("Could not find ports for back camera")
                    }
                } else {
                    logger.error("Could not add back camera output")
                }
                
                session.commitConfiguration()
            } else {
                logger.error("Cannot add required inputs to multi-cam session")
            }
            
            // Store session and start it
            self.multiCamSession = session
            self.captureSession = session
            
            logger.info("Starting multicam session")
            print("Starting multicam session")
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
            
        } catch {
            logger.error("Error setting up multi-camera mode: \(error.localizedDescription)")
            print("Error setting up multi-camera mode: \(error.localizedDescription)")
            // No fallback to single camera mode
        }
    }
    
    // Setup individual camera sessions for preview
    private func setupIndividualCameraPreviews() {
        // Setup front camera preview session
        if let frontDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            do {
                let frontInput = try AVCaptureDeviceInput(device: frontDevice)
                let frontSession = AVCaptureSession()
                frontSession.sessionPreset = .high
                
                if frontSession.canAddInput(frontInput) {
                    frontSession.addInput(frontInput)
                    self.frontCameraPreviewSession = frontSession
                    
                    // Start the session on a background thread
                    DispatchQueue.global(qos: .userInitiated).async {
                        frontSession.startRunning()
                    }
                    
                    print("Front camera preview session configured")
                }
            } catch {
                print("Error setting up front camera preview: \(error.localizedDescription)")
            }
        }
        
        // Setup back camera preview session
        if let backDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            do {
                let backInput = try AVCaptureDeviceInput(device: backDevice)
                let backSession = AVCaptureSession()
                backSession.sessionPreset = .high
                
                if backSession.canAddInput(backInput) {
                    backSession.addInput(backInput)
                    self.backCameraPreviewSession = backSession
                    
                    // Start the session on a background thread
                    DispatchQueue.global(qos: .userInitiated).async {
                        backSession.startRunning()
                    }
                    
                    print("Back camera preview session configured")
                }
            } catch {
                print("Error setting up back camera preview: \(error.localizedDescription)")
            }
        }
        
        // Set captureSession to multiCamSession
        captureSession = multiCamSession
    }
    
    // MARK: - Recording Methods
    
    // Prepare camera for recording
    func prepareForRecording() {
        logger.info("Preparing for recording")
        print("Preparing for recording")
    }
    
    // Start recording from both cameras
    func startRecording() {
        guard !isRecording else { return }
        
        // Reset error state
        recordingError = nil
        showRecordingError = false
        
        logger.info("Starting recording")
        print("Starting recording")
        
        // Reset counters
        activeRecordingCount = 0
        
        // Create temp recording directory in Documents folder (more reliable than system tmp)
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let tempRecordingDir = documentsPath.appendingPathComponent("TempRecordings", isDirectory: true)
        
        // Ensure the directory exists
        do {
            if !FileManager.default.fileExists(atPath: tempRecordingDir.path) {
                try FileManager.default.createDirectory(at: tempRecordingDir, withIntermediateDirectories: true)
            }
        } catch {
            logger.error("Failed to create temp recording directory: \(error.localizedDescription)")
            handleRecordingError("Failed to create recording directory")
            return
        }
        
        // Setup recording paths
        let frontURL = tempRecordingDir.appendingPathComponent("front_camera_\(Date().timeIntervalSince1970).mov")
        let backURL = tempRecordingDir.appendingPathComponent("back_camera_\(Date().timeIntervalSince1970).mov")
        
        self.frontCameraURL = frontURL
        self.backCameraURL = backURL
        
        // Start recording timers
        startRecordingTimer()
        
        // Start recording from front camera
        if let frontOutput = frontCameraOutput {
            activeRecordingCount += 1
            frontOutput.startRecording(to: frontURL, recordingDelegate: self)
            logger.info("Front camera recording started to: \(frontURL.path)")
        }
        
        // Start recording from back camera
        if let backOutput = backCameraOutput {
            activeRecordingCount += 1
            backOutput.startRecording(to: backURL, recordingDelegate: self)
            logger.info("Back camera recording started to: \(backURL.path)")
        }
        
        // Update recording state
        DispatchQueue.main.async {
            self.isRecording = true
            self.recordingInProgress = true
        }
    }
    
    // Stop recording from all cameras
    func stopRecording() {
        logger.info("Stopping recording")
        print("Stopping recording")
        
        // Stop front camera recording
        frontCameraOutput?.stopRecording()
        
        // Stop back camera recording
        backCameraOutput?.stopRecording()
        
        // Stop timer
        stopRecordingTimer()
        
        // Update state - recording will be set to false when all recordings have stopped
        DispatchQueue.main.async {
            self.recordingProgress = 0.0
        }
    }
    
    // MARK: - Timer Methods
    
    private func startRecordingTimer() {
        recordingStartTime = Date()
        
        // Create a timer to update recording progress
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
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
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingStartTime = nil
    }
    
    // MARK: - Cleanup Methods
    
    func cleanup() {
        // Stop any ongoing recording
        if isRecording {
            stopRecording()
        }
        
        // Stop sessions
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.multiCamSession?.stopRunning()
            self?.frontCameraPreviewSession?.stopRunning()
            self?.backCameraPreviewSession?.stopRunning()
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

// MARK: - AVCaptureFileOutputRecordingDelegate
extension DualCameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        logger.info("Recording started to \(fileURL.path)")
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        // Handle recording completion
        if let error = error {
            logger.error("Error recording to \(outputFileURL.path): \(error.localizedDescription)")
            print("Error recording: \(error.localizedDescription)")
            
            // Check if this was a clean stop despite the error (happens with some iOS versions)
            if let nsError = error as NSError?,
               let success = nsError.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool,
               success {
                // The recording was actually successful despite the error
                logger.info("Recording finished successfully despite error")
            } else {
                // This was a genuine error
                handleRecordingError("Recording failed: \(error.localizedDescription)")
            }
        } else {
            logger.info("Successfully recorded to \(outputFileURL.path)")
            print("Successfully recorded to: \(outputFileURL.lastPathComponent)")
            
            // Save to photo library if it's the back camera recording
            if output == backCameraOutput {
                saveToPhotoLibrary(url: outputFileURL)
            }
        }
        
        // Decrement active recording count
        activeRecordingCount -= 1
        
        // If all recordings have finished, update UI
        if activeRecordingCount <= 0 {
            DispatchQueue.main.async {
                self.isRecording = false
                self.recordingInProgress = false
                self.recordingProgress = 0.0
            }
        }
    }
    
    // Save video to photo library
    private func saveToPhotoLibrary(url: URL) {
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }) { success, error in
                    if success {
                        self.logger.info("Video saved to photo library")
                        print("Video saved to photo library")
                    } else if let error = error {
                        self.logger.error("Error saving video to photo library: \(error.localizedDescription)")
                        print("Error saving video: \(error.localizedDescription)")
                    }
                }
            }
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