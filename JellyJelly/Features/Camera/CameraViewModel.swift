import SwiftUI
import AVFoundation
import Combine

class CameraViewModel: ObservableObject {
    // MARK: - Properties
    
    @Published var isMultiCameraSupported: Bool = false
    @Published var showUnsupportedDeviceAlert: Bool = false
    @Published var cameraManager: DualCameraManager?
    
    // MARK: - Initialization
    
    init() {
        checkDeviceSupport()
    }
    
    // MARK: - Public Methods
    
    /// Checks if the device supports multi-camera functionality
    func checkDeviceSupport() {
        if #available(iOS 13.0, *), AVCaptureMultiCamSession.isMultiCamSupported {
            self.isMultiCameraSupported = true
            self.cameraManager = DualCameraManager()
        } else {
            self.isMultiCameraSupported = false
            self.showUnsupportedDeviceAlert = true
            // Not initializing cameraManager for unsupported devices
        }
    }
    
    /// Dismiss the unsupported device alert
    func dismissUnsupportedAlert() {
        self.showUnsupportedDeviceAlert = false
    }
}
