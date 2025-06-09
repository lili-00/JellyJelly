import Foundation
import AVFoundation
import UIKit

class LocalVideoStorage: ObservableObject {
    static let shared = LocalVideoStorage()
    
    @Published var videos: [LocalVideo] = []
    
    private let documentsDirectory: URL
    private let videosDirectoryName = "DualVideos"
    
    private init() {
        documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        createVideosDirectoryIfNeeded()
        loadVideos()
    }
    
    private func createVideosDirectoryIfNeeded() {
        let videosDirectory = documentsDirectory.appendingPathComponent(videosDirectoryName)
        if !FileManager.default.fileExists(atPath: videosDirectory.path) {
            try? FileManager.default.createDirectory(at: videosDirectory, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    func saveVideo(url: URL) {
        let videosDirectory = documentsDirectory.appendingPathComponent(videosDirectoryName)
        let fileName = "DualVideo_\(Date().timeIntervalSince1970).mp4"
        let destinationURL = videosDirectory.appendingPathComponent(fileName)
        
        do {
            // Move video to videos directory
            try FileManager.default.moveItem(at: url, to: destinationURL)
            
            // Generate thumbnail
            let thumbnail = generateVideoThumbnail(url: destinationURL)
            
            // Create local video object
            let localVideo = LocalVideo(
                id: UUID(),
                url: destinationURL,
                thumbnail: thumbnail,
                createdAt: Date(),
                duration: getVideoDuration(url: destinationURL)
            )
            
            // Add to videos array
            DispatchQueue.main.async {
                self.videos.insert(localVideo, at: 0) // Add to beginning
            }
            
        } catch {
            print("Failed to save video: \(error)")
        }
    }
    
    private func loadVideos() {
        let videosDirectory = documentsDirectory.appendingPathComponent(videosDirectoryName)
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: videosDirectory, includingPropertiesForKeys: [.creationDateKey], options: [])
            
            let videoURLs = fileURLs.filter { $0.pathExtension.lowercased() == "mp4" }
            
            var loadedVideos: [LocalVideo] = []
            
            for url in videoURLs {
                let thumbnail = generateVideoThumbnail(url: url)
                let creationDate = getFileCreationDate(url: url)
                let duration = getVideoDuration(url: url)
                
                let localVideo = LocalVideo(
                    id: UUID(),
                    url: url,
                    thumbnail: thumbnail,
                    createdAt: creationDate,
                    duration: duration
                )
                
                loadedVideos.append(localVideo)
            }
            
            // Sort by creation date (newest first)
            loadedVideos.sort { $0.createdAt > $1.createdAt }
            
            DispatchQueue.main.async {
                self.videos = loadedVideos
            }
            
        } catch {
            print("Failed to load videos: \(error)")
        }
    }
    
    private func generateVideoThumbnail(url: URL) -> UIImage? {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: CMTime(seconds: 1, preferredTimescale: 60), actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            print("Failed to generate thumbnail: \(error)")
            return nil
        }
    }
    
    private func getFileCreationDate(url: URL) -> Date {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.creationDate] as? Date ?? Date()
        } catch {
            return Date()
        }
    }
    
    private func getVideoDuration(url: URL) -> TimeInterval {
        let asset = AVAsset(url: url)
        return CMTimeGetSeconds(asset.duration)
    }
    
    func deleteVideo(_ video: LocalVideo) {
        do {
            try FileManager.default.removeItem(at: video.url)
            DispatchQueue.main.async {
                self.videos.removeAll { $0.id == video.id }
            }
        } catch {
            print("Failed to delete video: \(error)")
        }
    }
}

struct LocalVideo: Identifiable {
    let id: UUID
    let url: URL
    let thumbnail: UIImage?
    let createdAt: Date
    let duration: TimeInterval
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
} 