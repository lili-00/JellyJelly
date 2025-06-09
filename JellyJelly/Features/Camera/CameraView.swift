import SwiftUI
import AVFoundation

struct CameraView: View {
    @StateObject private var viewModel = CameraViewModel()
    @State private var showingSettings = false
    @State private var recordingTimeSelection: DualCameraManager.RecordingTime = .fifteenSeconds
    
    var body: some View {
        ZStack {
            if viewModel.isMultiCameraSupported {
                // Camera preview
                if let cameraManager = viewModel.cameraManager {
                    ZStack {
                        CameraPreviewContainerView(cameraManager: cameraManager)
                            .edgesIgnoringSafeArea(.all)
                        
                        // UI Controls overlay
                        VStack {
                            // Top controls
                            HStack {
                                Button(action: {
                                    showingSettings.toggle()
                                }) {
                                    Image(systemName: "gear")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                        .padding()
                                }
                                
                                Spacer()
                                
                                // Timer selection
                                HStack(spacing: 20) {
                                    ForEach(DualCameraManager.RecordingTime.allCases) { time in
                                        Button(action: {
                                            cameraManager.recordingTime = time
                                            recordingTimeSelection = time
                                        }) {
                                            Text(time.displayName)
                                                .foregroundColor(.white)
                                                .padding(.vertical, 6)
                                                .padding(.horizontal, 12)
                                                .background(
                                                    Capsule()
                                                        .fill(recordingTimeSelection == time ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                                                )
                                        }
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal)
                            
                            Spacer()
                            
                            // Record button
                            Button(action: {
                                if cameraManager.recordingInProgress {
                                    cameraManager.stopRecording()
                                } else {
                                    // Prepare camera before recording
                                    cameraManager.prepareForRecording()
                                    cameraManager.startRecording()
                                }
                            }) {
                                ZStack {
                                    Circle()
                                        .stroke(Color.white, lineWidth: 4)
                                        .frame(width: 80, height: 80)
                                    
                                    // Recording progress indicator
                                    Circle()
                                        .trim(from: 0, to: cameraManager.recordingProgress)
                                        .stroke(Color.red, lineWidth: 4)
                                        .frame(width: 80, height: 80)
                                        .rotationEffect(.degrees(-90))
                                    
                                    // Record button inner circle
                                    Circle()
                                        .fill(cameraManager.recordingInProgress ? Color.red : Color.white)
                                        .frame(width: 70, height: 70)
                                }
                            }
                            .padding(.bottom, 40)
                        }
                        
                        // Permission alert
                        if cameraManager.showPermissionAlert {
                            PermissionAlertView()
                                .transition(.opacity)
                                .animation(.easeInOut, value: cameraManager.showPermissionAlert)
                        }
                    }
                    .alert(isPresented: Binding<Bool>(
                        get: { cameraManager.showRecordingError },
                        set: { cameraManager.showRecordingError = $0 }
                    )) {
                        Alert(
                            title: Text("Recording Failed"),
                            message: Text(cameraManager.recordingError ?? "Could not record video. Please try again."),
                            dismissButton: .default(Text("OK"))
                        )
                    }
                }
            } else {
                // Device doesn't support multi-camera
                UnsupportedDeviceView()
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .alert(isPresented: $viewModel.showUnsupportedDeviceAlert) {
            Alert(
                title: Text("Device Not Supported"),
                message: Text("This device does not support simultaneous use of multiple cameras. JellyJelly requires a device with an A12 Bionic chip or newer (iPhone XS/XR or newer)."),
                dismissButton: .default(Text("OK")) {
                    viewModel.dismissUnsupportedAlert()
                }
            )
        }
    }
}

// Unsupported device view
struct UnsupportedDeviceView: View {
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.yellow)
                
                Text("Device Not Supported")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("JellyJelly requires a device that supports simultaneous use of multiple cameras (iPhone XS/XR or newer with A12 Bionic chip or later).")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .padding(.horizontal)
                
                Text("You can still use other features of the app.")
                    .foregroundColor(.gray)
                    .padding(.top)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.8))
            )
            .padding(30)
        }
    }
}

// Permission alert view
struct PermissionAlertView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 50))
                .foregroundColor(.red)
            
            Text("Camera & Microphone Access Required")
                .font(.headline)
            
            Text("JellyJelly needs access to your camera and microphone to record videos. Please grant these permissions in Settings.")
                .multilineTextAlignment(.center)
                .font(.body)
                .padding(.horizontal)
            
            Button(action: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }) {
                Text("Open Settings")
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 30)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(radius: 10)
        )
        .padding(30)
    }
}

// Settings view
struct SettingsView: View {
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Recording")) {
                    HStack {
                        Text("Video Quality")
                        Spacer()
                        Text("High")
                            .foregroundColor(.gray)
                    }
                    
                    Toggle("Save to Photos", isOn: .constant(true))
                }
                
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.gray)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Settings")
        }
    }
}

// Container view to handle different camera preview modes
struct CameraPreviewContainerView: View {
    @ObservedObject var cameraManager: DualCameraManager
    
    var body: some View {
        GeometryReader { geometry in
            // Debug state of camera manager
            Group {
                Text("Multi-camera mode active")
                    .font(.system(size: 0.1))
                    .hidden()
                    .onAppear {
                        print("🎥 Camera preview active")
                    }
            }
            
            // Multi-camera view - split screen
            VStack(spacing: 0) {
                // Top half - Front camera
                FrontCameraPreviewView()
                    .environmentObject(cameraManager)
                    .frame(height: geometry.size.height / 2)
                
                // Bottom half - Back camera
                BackCameraPreviewView()
                    .environmentObject(cameraManager)
                    .frame(height: geometry.size.height / 2)
            }
        }
    }
}

// MARK: - Camera Preview Views

// Front camera preview
struct FrontCameraPreviewView: UIViewRepresentable {
    @EnvironmentObject var cameraManager: DualCameraManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        
        // Tag for debugging
        view.tag = 1001
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Clear existing sublayers first
        uiView.layer.sublayers?.filter { $0 is AVCaptureVideoPreviewLayer }.forEach { $0.removeFromSuperlayer() }
        
        // Add layer if available
        if let layer = cameraManager.frontPreviewLayer {
            layer.videoGravity = .resizeAspectFill
            layer.frame = uiView.bounds
            
            // Only add if not already a sublayer
            let existingLayers = uiView.layer.sublayers?.compactMap { $0 as? AVCaptureVideoPreviewLayer } ?? []
            if !existingLayers.contains(layer) {
                uiView.layer.addSublayer(layer)
                
                // Force layout
                layer.frame = uiView.bounds
                
                // Debug
                print("Added front camera preview layer to view")
                
                // Force update orientation for portrait mode
                if let connection = layer.connection, connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                
                // Ensure mirroring for front camera
                if let connection = layer.connection {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = true
                }
            }
        }
    }
}

// Back camera preview
struct BackCameraPreviewView: UIViewRepresentable {
    @EnvironmentObject var cameraManager: DualCameraManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        
        // Tag for debugging
        view.tag = 1002
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Clear existing sublayers first
        uiView.layer.sublayers?.filter { $0 is AVCaptureVideoPreviewLayer }.forEach { $0.removeFromSuperlayer() }
        
        // Add layer if available
        if let layer = cameraManager.backPreviewLayer {
            layer.videoGravity = .resizeAspectFill
            layer.frame = uiView.bounds
            
            // Only add if not already a sublayer
            let existingLayers = uiView.layer.sublayers?.compactMap { $0 as? AVCaptureVideoPreviewLayer } ?? []
            if !existingLayers.contains(layer) {
                uiView.layer.addSublayer(layer)
                
                // Force layout
                layer.frame = uiView.bounds
                
                // Debug
                print("Added back camera preview layer to view")
                
                // Force update orientation for portrait mode
                if let connection = layer.connection, connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
        }
    }
}

// Standard camera preview view (not used in this implementation but kept for reference)
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let position: AVCaptureDevice.Position
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        
        // Set orientation based on what's supported
        if let connection = previewLayer.connection {
            if connection.isVideoRotationAngleSupported(.pi/2) {
                connection.videoRotationAngle = .pi/2 // 90 degrees (portrait)
            } else if connection.isVideoOrientationSupported {
                // Fall back to deprecated API with warning
                #if DEBUG
                print("Warning: videoRotationAngle not supported in CameraPreviewView, falling back to videoOrientation")
                #endif
                connection.videoOrientation = .portrait
            }
            
            // Apply mirroring for front camera
            if position == .front {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
        
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiView.bounds
        }
    }
}

#Preview {
    CameraView()
} 
