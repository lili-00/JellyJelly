import SwiftUI
import AVFoundation

struct CameraView: View {
    @StateObject private var cameraManager = DualCameraManager()
    @State private var showingSettings = false
    @State private var recordingTimeSelection: DualCameraManager.RecordingTime = .fifteenSeconds
    
    var body: some View {
        ZStack {
            // Camera preview
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
                    
                    // If single camera mode, add switch camera button
                    if !cameraManager.isMultiCameraMode {
                        Button(action: {
                            cameraManager.switchCamera()
                        }) {
                            Image(systemName: "camera.rotate")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .padding()
                        }
                    }
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
        .sheet(isPresented: $showingSettings) {
            SettingsView()
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
                if cameraManager.isMultiCameraMode {
                    Text("Multi-camera mode: \(cameraManager.isMultiCameraMode ? "Yes" : "No")")
                        .font(.system(size: 0.1))
                        .hidden()
                        .onAppear {
                            print("🎥 Multi-camera mode: \(cameraManager.isMultiCameraMode)")
                            print("📱 Front session: \(String(describing: cameraManager.frontCameraPreviewSession))")
                            print("📱 Back session: \(String(describing: cameraManager.backCameraPreviewSession))")
                        }
                }
            }
            
            if cameraManager.isMultiCameraMode,
               let frontSession = cameraManager.frontCameraPreviewSession,
               let backSession = cameraManager.backCameraPreviewSession {
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
            } else {
                // Single camera view - full screen
                if let session = cameraManager.captureSession {
                    CameraPreviewView(session: session, position: cameraManager.activePosition)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Fallback if no session is available
                    ZStack {
                        Color.black.edgesIgnoringSafeArea(.all)
                        Text("Camera initializing...")
                            .foregroundColor(.white)
                            .onAppear {
                                print("⚠️ No camera session available!")
                                print("📱 CaptureSession: \(String(describing: cameraManager.captureSession))")
                            }
                    }
                }
            }
        }
    }
}

// Standard camera preview view for single camera mode
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let position: AVCaptureDevice.Position
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        
        // Set proper orientation
        if let connection = previewLayer.connection {
            connection.videoOrientation = .portrait
            
            if position == .front {
                // IMPORTANT: Must set automaticallyAdjustsVideoMirroring to false BEFORE setting isVideoMirrored
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
        
        view.layer.addSublayer(previewLayer)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiView.bounds
            
            // Update orientation if needed
            if let connection = previewLayer.connection {
                connection.videoOrientation = .portrait
            }
        }
    }
}

// Front camera preview (uses UIKit for better control)
struct FrontCameraPreviewView: UIViewRepresentable {
    @EnvironmentObject var cameraManager: DualCameraManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        
        // Configure a preview layer for the front camera
        let previewLayer = AVCaptureVideoPreviewLayer()
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        
        // Use the session from camera manager
        if let frontSession = cameraManager.frontCameraPreviewSession {
            previewLayer.session = frontSession
            
            // Set proper orientation and mirroring
            if let connection = previewLayer.connection {
                connection.videoOrientation = .portrait
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        } else {
            print("⚠️ Front camera session is nil")
        }
        
        view.layer.addSublayer(previewLayer)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiView.bounds
        }
    }
}

// Back camera preview (uses UIKit for better control)
struct BackCameraPreviewView: UIViewRepresentable {
    @EnvironmentObject var cameraManager: DualCameraManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        
        // Configure a preview layer for the back camera
        let previewLayer = AVCaptureVideoPreviewLayer()
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        
        // Use the session from camera manager
        if let backSession = cameraManager.backCameraPreviewSession {
            previewLayer.session = backSession
            
            // Set proper orientation
            if let connection = previewLayer.connection {
                connection.videoOrientation = .portrait
            }
        } else {
            print("⚠️ Back camera session is nil")
        }
        
        view.layer.addSublayer(previewLayer)
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