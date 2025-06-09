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
    
    // Fallback for older devices
    private var fallbackSession = AVCaptureSession()
    
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
    private var movieFileOutput: AVCaptureMovieFileOutput?
    
    // Devices
    private var frontCamera: AVCaptureDevice?
    private var backCamera: AVCaptureDevice?
    
    // Status tracking
    private var isMultiCamSupported = false
    private var activeCamera: AVCaptureDevice.Position = .back
    
    // Public properties
    var activePosition: AVCaptureDevice.Position {
        return activeCamera
    }
    
    var isMultiCameraMode: Bool {
        return isMultiCamSupported
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
            
            // Initialize camera sessions based on device capabilities
            if #available(iOS 13.0, *), AVCaptureMultiCamSession.isMultiCamSupported {
                self.logger.info("Setting up multi-camera mode")
                print("Setting up multi-camera mode")
                self.setupMultiCameraMode()
                self.isMultiCamSupported = true
            } else {
                self.logger.info("Setting up single-camera mode")
                print("Setting up single-camera mode")
                self.setupSingleCameraMode()
                self.isMultiCamSupported = false
            }
            
            // Log camera session status
            DispatchQueue.main.async {
                self.isSetupComplete = true
                self.logger.info("Camera setup complete. Sessions: captureSession=\(self.captureSession != nil ? "initialized" : "nil"), frontSession=\(self.frontCameraPreviewSession != nil ? "initialized" : "nil"), backSession=\(self.backCameraPreviewSession != nil ? "initialized" : "nil")")
                print("Camera setup complete: multiCam=\(self.isMultiCamSupported), captureSession=\(self.captureSession != nil ? "initialized" : "nil")")
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
        // Create individual camera sessions for preview (helps with black screen issues)
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
            // Fall back to single camera mode
            setupSingleCameraMode()
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
        
        // Set captureSession to multiCamSession for fallback
        captureSession = multiCamSession
    }
    
    // Setup for devices that don't support multi-camera
    private func setupSingleCameraMode() {
        let session = AVCaptureSession()
        session.sessionPreset = .high
        
        do {
            // Start with back camera
            if let backDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                self.backCamera = backDevice
                let backInput = try AVCaptureDeviceInput(device: backDevice)
                self.backCameraInput = backInput
                
                if session.canAddInput(backInput) {
                    session.addInput(backInput)
                    logger.info("Added back camera input to single camera session")
                } else {
                    logger.error("Could not add back camera input to session")
                }
            } else {
                logger.error("No back camera device available for single camera mode")
            }
            
            // Also discover front camera for switching
            if let frontDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                self.frontCamera = frontDevice
                logger.info("Found front camera for switching: \(frontDevice.localizedName)")
            } else {
                logger.error("No front camera device available for switching")
            }
            
            // Add audio input
            if let audioDevice = AVCaptureDevice.default(for: .audio) {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                    logger.info("Added audio input to single camera session")
                } else {
                    logger.error("Could not add audio input to session")
                }
            } else {
                logger.error("No audio device available")
            }
            
            // Add movie output
            let movieOutput = AVCaptureMovieFileOutput()
            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
                self.movieFileOutput = movieOutput
                self.backCameraOutput = movieOutput // Use the same output for fallback mode
                
                if let connection = movieOutput.connection(with: .video) {
                    connection.videoOrientation = .portrait
                    logger.info("Configured movie output for single camera session")
                }
            } else {
                logger.error("Could not add movie output to session")
            }
            
            self.captureSession = session
            self.fallbackSession = session
            
            // Create a simple back camera preview session too
            setupSingleBackCameraPreview()
            
            logger.info("Starting single camera session")
            print("Starting single camera session")
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        } catch {
            logger.error("Error setting up single camera mode: \(error.localizedDescription)")
            print("Error setting up single camera mode: \(error.localizedDescription)")
        }
    }
    
    // Set up a simple back camera preview session for single camera mode
    private func setupSingleBackCameraPreview() {
        let backSession = AVCaptureSession()
        backSession.sessionPreset = .high
        
        if let backDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            do {
                let backInput = try AVCaptureDeviceInput(device: backDevice)
                if backSession.canAddInput(backInput) {
                    backSession.addInput(backInput)
                    self.backCameraPreviewSession = backSession
                    
                    // Start session
                    DispatchQueue.global(qos: .userInitiated).async {
                        backSession.startRunning()
                    }
                    
                    logger.info("Back camera preview session configured for single camera mode")
                    print("Back camera preview session configured for single camera mode")
                }
            } catch {
                logger.error("Error setting up back camera preview for single camera mode: \(error.localizedDescription)")
                print("Error setting up back camera preview: \(error.localizedDescription)")
            }
        }
    }
    
    // Reset camera sessions
    private func resetCameraSessions() {
        // Stop any running sessions
        if #available(iOS 13.0, *), let multiCamSession = multiCamSession, multiCamSession.isRunning {
            multiCamSession.stopRunning()
        }
        
        if fallbackSession.isRunning {
            fallbackSession.stopRunning()
        }
        
        if let frontSession = frontCameraPreviewSession, frontSession.isRunning {
            frontSession.stopRunning()
        }
        
        if let backSession = backCameraPreviewSession, backSession.isRunning {
            backSession.stopRunning()
        }
        
        // Remove all inputs and outputs from fallback session
        for input in fallbackSession.inputs {
            fallbackSession.removeInput(input)
        }
        
        for output in fallbackSession.outputs {
            fallbackSession.removeOutput(output)
        }
        
        // Reset all references
        multiCamSession = nil
        frontCameraInput = nil
        backCameraInput = nil
        frontCameraOutput = nil
        backCameraOutput = nil
        movieFileOutput = nil
        captureSession = nil
        frontCameraPreviewSession = nil
        backCameraPreviewSession = nil
        
        // Stop progress timer if running
        stopRecordingTimer()
    }
    
    // MARK: - Camera Control
    
    // Switch between front and back cameras in single-camera mode
    func switchCamera() {
        guard !isMultiCamSupported, let session = captureSession else { return }
        guard !isRecording else { return }
        
        session.beginConfiguration()
        
        // Remove current camera input
        session.inputs.forEach { input in
            if input is AVCaptureDeviceInput, let deviceInput = input as? AVCaptureDeviceInput, deviceInput.device.hasMediaType(.video) {
                session.removeInput(deviceInput)
            }
        }
        
        do {
            // Add the opposite camera
            let newPosition: AVCaptureDevice.Position = (activeCamera == .back) ? .front : .back
            
            if let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) {
                let newInput = try AVCaptureDeviceInput(device: newDevice)
                
                if session.canAddInput(newInput) {
                    session.addInput(newInput)
                    
                    // Update connection for front camera mirroring
                    if let connection = movieFileOutput?.connection(with: .video) {
                        connection.videoOrientation = .portrait
                        
                        if newPosition == .front {
                            connection.automaticallyAdjustsVideoMirroring = false
                            connection.isVideoMirrored = true
                        } else {
                            connection.isVideoMirrored = false
                        }
                    }
                    
                    // Update active position
                    self.activeCamera = newPosition
                }
            }
        } catch {
            print("Error switching camera: \(error.localizedDescription)")
        }
        
        session.commitConfiguration()
    }
    
    // MARK: - Recording
    
    // Start recording with the appropriate camera setup
    func startRecording() {
        guard !isRecording else { return }
        
        print("Starting dual camera recording...")
        
        // Create temporary file URLs for recording
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = Date().timeIntervalSince1970
        frontCameraURL = tempDir.appendingPathComponent("frontCamera_\(timestamp).mp4")
        backCameraURL = tempDir.appendingPathComponent("backCamera_\(timestamp).mp4")
        
        var recordingStarted = false
        activeRecordingCount = 0
        
        // Start recording with both cameras when in multi-camera mode
        if isMultiCamSupported {
            // Start front camera recording
            if let frontOutput = frontCameraOutput, let frontURL = frontCameraURL {
                if !frontOutput.isRecording {
                    ensureRecordingConnections(for: frontOutput)
                    frontOutput.startRecording(to: frontURL, recordingDelegate: self)
                    activeRecordingCount += 1
                    recordingStarted = true
                    print("Front camera recording started")
                }
            }
            
            // Start back camera recording
            if let backOutput = backCameraOutput, let backURL = backCameraURL {
                if !backOutput.isRecording {
                    ensureRecordingConnections(for: backOutput)
                    backOutput.startRecording(to: backURL, recordingDelegate: self)
                    activeRecordingCount += 1
                    recordingStarted = true
                    print("Back camera recording started")
                }
            }
        } else {
            // Fallback to single camera recording
            let singleURL = tempDir.appendingPathComponent("singleCamera_\(timestamp).mp4")
            backCameraURL = singleURL // Store in backCameraURL for simplicity
            
            if let output = movieFileOutput {
                if !output.isRecording {
                    ensureRecordingConnections(for: output)
                    output.startRecording(to: singleURL, recordingDelegate: self)
                    activeRecordingCount += 1
                    recordingStarted = true
                    print("Single camera recording started")
                }
            }
        }
        
        if recordingStarted {
            // Set up recording timer and progress tracking
            isRecording = true
            recordingInProgress = true
            recordingProgress = 0.0
            recordingStartTime = Date()
            
            // Start timer to update progress and auto-stop recording
            startRecordingTimer()
        } else {
            print("Failed to start any recording")
        }
    }
    
    // Stop all active recordings
    func stopRecording() {
        print("Stopping all camera recordings...")
        
        // Stop all active recordings
        if let output = frontCameraOutput, output.isRecording {
            output.stopRecording()
        }
        
        if let output = backCameraOutput, output.isRecording {
            output.stopRecording()
        }
        
        if let output = movieFileOutput, output.isRecording {
            output.stopRecording()
        }
        
        // Clean up timer
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Reset state (but keep isRecording true until finishRecording is called)
        recordingProgress = 1.0
    }
    
    // Ensure connections are properly set up for recording
    private func ensureRecordingConnections(for output: AVCaptureMovieFileOutput) {
        if let connection = output.connection(with: .video) {
            // Set portrait orientation
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            
            // Set stabilization if supported
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
            
            // Set quality
            output.movieFragmentInterval = .invalid // Write one continuous movie file
        }
    }
    
    // Timer for recording progress and auto-stop
    private func startRecordingTimer() {
        recordingTimer?.invalidate()
        
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self, let startTime = self.recordingStartTime else {
                timer.invalidate()
                return
            }
            
            let elapsedTime = Date().timeInterval(since: startTime)
            let duration = self.recordingTime.rawValue
            let progress = min(elapsedTime / duration, 1.0)
            
            DispatchQueue.main.async {
                self.recordingProgress = progress
            }
            
            // Auto-stop when reaching the selected duration
            if elapsedTime >= duration {
                self.stopRecording()
            }
        }
    }
    
    // Call this method when all recordings finish
    private func finishRecording() {
        print("Finishing recording process...")
        
        // For single camera mode, just save the video directly
        if !isMultiCamSupported, let singleURL = backCameraURL {
            saveSingleVideoAndNotify(singleURL)
            return
        }
        
        // For dual camera mode, compose videos if both are available
        if let frontURL = frontCameraURL, let backURL = backCameraURL {
            print("Composing dual camera video...")
            
            // Create a composition of both videos
            composeDualVideo(frontURL: frontURL, backURL: backURL) { [weak self] composedURL in
                guard let self = self else { return }
                
                if let finalURL = composedURL {
                    self.saveSingleVideoAndNotify(finalURL)
                } else {
                    // If composition fails, use back camera video as fallback
                    print("Composition failed, using back camera video as fallback")
                    self.saveSingleVideoAndNotify(backURL)
                }
            }
        } else if let singleURL = backCameraURL ?? frontCameraURL {
            // If only one video is available, use that
            print("Only one camera recording available, using it")
            saveSingleVideoAndNotify(singleURL)
        } else {
            print("No video URLs available to save")
            
            // Reset recording state
            isRecording = false
            recordingInProgress = false
        }
    }
    
    private func saveSingleVideoAndNotify(_ url: URL) {
        // Save the video
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            LocalVideoStorage.shared.saveVideo(url: url)
            
            // Reset recording state
            self.isRecording = false
            self.recordingInProgress = false
            
            // Notify that a video was recorded
            NotificationCenter.default.post(name: .videoRecorded, object: nil)
            
            print("Successfully saved video and posted notification")
            
            // Reset recording URLs
            self.frontCameraURL = nil
            self.backCameraURL = nil
            self.activeRecordingCount = 0
        }
    }
    
    // Compose dual videos into a single split-screen video
    private func composeDualVideo(frontURL: URL, backURL: URL, completion: @escaping (URL?) -> Void) {
        // Create a composition of the two videos
        let composition = AVMutableComposition()
        
        // Get front and back video assets
        let frontAsset = AVAsset(url: frontURL)
        let backAsset = AVAsset(url: backURL)
        
        // Create output URL for the composed video
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("dualVideo_\(Date().timeIntervalSince1970).mp4")
        
        // Create video tracks for front and back cameras
        guard let backTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let frontTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            print("Failed to create composition video tracks")
            completion(nil)
            return
        }
        
        // Create audio track
        guard let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            print("Failed to create composition audio track")
            completion(nil)
            return
        }
        
        do {
            // Determine the shorter duration
            let frontDuration = frontAsset.duration
            let backDuration = backAsset.duration
            let duration = CMTimeCompare(frontDuration, backDuration) < 0 ? frontDuration : backDuration
            let timeRange = CMTimeRange(start: .zero, duration: duration)
            
            // Get video tracks from each asset
            guard let backVideoTrack = backAsset.tracks(withMediaType: .video).first,
                  let frontVideoTrack = frontAsset.tracks(withMediaType: .video).first else {
                print("Could not find video tracks in assets")
                completion(nil)
                return
            }
            
            // Insert back camera video
            try backTrack.insertTimeRange(timeRange, of: backVideoTrack, at: .zero)
            
            // Insert front camera video
            try frontTrack.insertTimeRange(timeRange, of: frontVideoTrack, at: .zero)
            
            // Try to get audio from back camera and add it (we prefer back camera audio)
            if let backAudioTrack = backAsset.tracks(withMediaType: .audio).first {
                try compositionAudioTrack.insertTimeRange(timeRange, of: backAudioTrack, at: .zero)
            } else if let frontAudioTrack = frontAsset.tracks(withMediaType: .audio).first {
                try compositionAudioTrack.insertTimeRange(timeRange, of: frontAudioTrack, at: .zero)
            }
            
            // Get natural size from back camera for composition
            let videoSize = backVideoTrack.naturalSize
            
            // Create video composition for layout
            let videoComposition = AVMutableVideoComposition()
            videoComposition.renderSize = CGSize(width: videoSize.width, height: videoSize.height)
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
            
            // Create instruction
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = timeRange
            
            // Create layer instructions
            let backLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: backTrack)
            let frontLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: frontTrack)
            
            // Setup transforms for front camera (position in top half of screen)
            let frontTransform = CGAffineTransform(scaleX: 0.5, y: 0.5)
                .concatenating(CGAffineTransform(translationX: videoSize.width * 0.25, y: videoSize.height * 0.25))
            
            // Apply transforms
            frontLayerInstruction.setTransform(frontTransform, at: .zero)
            
            // Add instructions (front camera on top of back camera)
            instruction.layerInstructions = [backLayerInstruction, frontLayerInstruction]
            videoComposition.instructions = [instruction]
            
            // Export the composed video
            guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
                print("Failed to create export session")
                completion(nil)
                return
            }
            
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4
            exportSession.videoComposition = videoComposition
            exportSession.shouldOptimizeForNetworkUse = true
            
            // Start export
            exportSession.exportAsynchronously {
                DispatchQueue.main.async {
                    switch exportSession.status {
                    case .completed:
                        print("Successfully exported composed video")
                        completion(outputURL)
                    default:
                        print("Failed to export: \(exportSession.status), error: \(exportSession.error?.localizedDescription ?? "unknown")")
                        completion(nil)
                    }
                }
            }
        } catch {
            print("Error creating composition: \(error.localizedDescription)")
            completion(nil)
        }
    }
    
    // MARK: - Video Composition
    
    // Compose final video from front and back camera recordings
    func composeVideo(completion: @escaping (URL?) -> Void) {
        guard let frontURL = frontCameraURL, let backURL = backCameraURL else {
            completion(nil)
            return
        }
        
        let composition = AVMutableComposition()
        let videoComposition = AVMutableVideoComposition()
        
        // Create tracks
        guard let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            completion(nil)
            return
        }
        
        do {
            // Load assets
            let frontAsset = AVAsset(url: frontURL)
            let backAsset = AVAsset(url: backURL)
            
            // Get tracks
            guard let frontVideoTrack = frontAsset.tracks(withMediaType: .video).first,
                  let backVideoTrack = backAsset.tracks(withMediaType: .video).first,
                  let backAudioTrack = backAsset.tracks(withMediaType: .audio).first else {
                completion(nil)
                return
            }
            
            // Get shorter duration to sync videos
            let duration = CMTimeMinimum(frontAsset.duration, backAsset.duration)
            let timeRange = CMTimeRangeMake(start: .zero, duration: duration)
            
            // Add back camera video
            try compositionVideoTrack.insertTimeRange(timeRange, of: backVideoTrack, at: .zero)
            
            // Add audio from back camera
            try compositionAudioTrack.insertTimeRange(timeRange, of: backAudioTrack, at: .zero)
            
            // Setup video composition
            videoComposition.renderSize = CGSize(width: backVideoTrack.naturalSize.width, height: backVideoTrack.naturalSize.height)
            videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
            
            // Create layered instruction
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = timeRange
            
            // Back camera layer instruction
            let backLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
            
            // Apply transforms for correct orientation
            var backTransform = CGAffineTransform.identity
            let backVideoAngle = atan2(backVideoTrack.preferredTransform.b, backVideoTrack.preferredTransform.a)
            backTransform = backTransform.rotated(by: backVideoAngle)
            backLayerInstruction.setTransform(backTransform, at: .zero)
            
            // Create PiP effect with front camera
            let frontVideoLayer = CALayer()
            let videoLayer = CALayer()
            let outputLayer = CALayer()
            
            // Load front camera video for overlay
            let frontPixelBuffer = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
            let frontItem = AVPlayerItem(asset: frontAsset)
            frontItem.add(frontPixelBuffer)
            
            let frontLayer = AVSynchronizedLayer(playerItem: frontItem)
            frontLayer.frame = CGRect(x: 0, y: 0, width: videoComposition.renderSize.width, height: videoComposition.renderSize.height / 2)
            
            // Configure layers
            videoLayer.frame = CGRect(x: 0, y: 0, width: videoComposition.renderSize.width, height: videoComposition.renderSize.height)
            frontVideoLayer.frame = CGRect(x: 0, y: 0, width: videoComposition.renderSize.width, height: videoComposition.renderSize.height / 2)
            outputLayer.frame = CGRect(x: 0, y: 0, width: videoComposition.renderSize.width, height: videoComposition.renderSize.height)
            
            // Add layers
            outputLayer.addSublayer(videoLayer)
            outputLayer.addSublayer(frontVideoLayer)
            
            // Set instructions
            instruction.layerInstructions = [backLayerInstruction]
            videoComposition.instructions = [instruction]
            
            // Render animation
            let animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: outputLayer)
            videoComposition.animationTool = animationTool
            
            // Create export session
            let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("finalVideo_\(Date().timeIntervalSince1970).mov")
            
            guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
                completion(nil)
                return
            }
            
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mov
            exportSession.videoComposition = videoComposition
            
            // Export composed video
            exportSession.exportAsynchronously {
                DispatchQueue.main.async {
                    if exportSession.status == .completed {
                        // Try to save to Photos library
                        self.saveToPhotos(videoURL: outputURL) { success, error in
                            if success {
                                print("Video saved to Photos library")
                            } else if let error = error {
                                print("Failed to save to Photos library: \(error.localizedDescription)")
                            }
                        }
                        completion(outputURL)
                    } else {
                        print("Failed to export: \(exportSession.error?.localizedDescription ?? "Unknown error")")
                        completion(nil)
                    }
                }
            }
            
        } catch {
            print("Error composing video: \(error.localizedDescription)")
            completion(nil)
        }
    }
    
    // MARK: - Video Saving
    
    // Save video to Photos library
    func saveToPhotos(videoURL: URL, completion: @escaping (Bool, Error?) -> Void) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    completion(false, CameraError.permissionDenied)
                }
                return
            }
            
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
            }) { success, error in
                DispatchQueue.main.async {
                    completion(success, error)
                }
            }
        }
    }
    
    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingStartTime = nil
    }
    
    // MARK: - Debug Helpers
    
    private func logCameraStatus() {
        print("=== CAMERA STATUS ===")
        print("Multi-camera supported: \(isMultiCamSupported)")
        print("Active camera position: \(activeCamera)")
        
        if let multiCam = multiCamSession {
            print("MultiCamSession: \(multiCam)")
            print("MultiCamSession running: \(multiCam.isRunning)")
        } else {
            print("MultiCamSession: nil")
        }
        
        print("Capture session: \(String(describing: captureSession))")
    }
    
    // Helper methods for debugging and preparation
    func prepareForRecording() {
        // Output camera status
        print("=== CAMERA STATUS ===")
        print("Multi-camera supported: \(isMultiCamSupported)")
        print("Capture session running: \(captureSession?.isRunning ?? false)")
        
        // Ensure the session is running
        if let session = captureSession, !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
                print("Started capture session")
            }
        }
        
        // Check if recording is possible with any output
        let canRecord = (movieFileOutput != nil) || (frontCameraOutput != nil) || (backCameraOutput != nil)
        print("Can record: \(canRecord)")
        print("===================")
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
extension DualCameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        print("Successfully started recording to \(fileURL.lastPathComponent)")
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        print("Finished recording to \(outputFileURL.lastPathComponent)")
        
        // Check if there was an error
        if let error = error {
            let errorDesc = error.localizedDescription
            print("Recording error: \(errorDesc)")
            
            // Check if this was a normal stop despite the error
            let userInfo = (error as NSError).userInfo
            guard let recordingSuccessfullyFinished = userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool,
                  recordingSuccessfullyFinished else {
                print("Recording failed: \(errorDesc)")
                
                // Clear the URL based on which output failed
                if output == frontCameraOutput {
                    frontCameraURL = nil
                } else if output == backCameraOutput {
                    backCameraURL = nil
                }
                
                // Decrement active recording count
                activeRecordingCount -= 1
                
                // If all recordings failed, reset recording state
                if activeRecordingCount <= 0 {
                    DispatchQueue.main.async {
                        self.isRecording = false
                        self.recordingInProgress = false
                    }
                }
                return
            }
            
            print("Recording successfully finished despite error")
        }
        
        // Decrement active recording count
        activeRecordingCount -= 1
        
        // For single camera mode, finish immediately
        if !isMultiCamSupported {
            finishRecording()
            return
        }
        
        // For multi-camera mode, wait until all recordings finish
        if activeRecordingCount <= 0 {
            finishRecording()
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