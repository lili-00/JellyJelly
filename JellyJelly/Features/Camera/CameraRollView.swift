import SwiftUI
import AVKit

struct CameraRollView: View {
    @StateObject private var videoStorage = LocalVideoStorage.shared
    @State private var selectedVideo: LocalVideo?
    @State private var showingVideoPlayer = false
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if videoStorage.videos.isEmpty {
                    // Empty state
                    VStack(spacing: 20) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No videos yet")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        
                        Text("Record your first dual POV video\nusing the camera tab")
                            .font(.body)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(videoStorage.videos) { video in
                                VideoThumbnailView(video: video) {
                                    selectedVideo = video
                                    showingVideoPlayer = true
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.top, 10)
                    }
                }
            }
            .navigationTitle("Camera Roll")
            .navigationBarTitleDisplayMode(.large)
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showingVideoPlayer) {
            if let video = selectedVideo {
                VideoPlayerSheet(video: video, isPresented: $showingVideoPlayer)
            }
        }
        .onAppear {
            // Refresh the video list when view appears
            videoStorage.objectWillChange.send()
        }
        .onReceive(NotificationCenter.default.publisher(for: .videoRecorded)) { _ in
            // Refresh the video list when a new video is recorded
            videoStorage.objectWillChange.send()
        }
    }
}

struct VideoThumbnailView: View {
    let video: LocalVideo
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Thumbnail image
                if let thumbnail = video.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(9/16, contentMode: .fill)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .aspectRatio(9/16, contentMode: .fill)
                        .overlay(
                            Image(systemName: "video")
                                .font(.title)
                                .foregroundColor(.gray)
                        )
                }
                
                // Play button overlay
                Circle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .offset(x: 2) // Slight offset to center the play icon
                    )
                
                // Duration badge
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(video.formattedDuration)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(4)
                            .padding(.trailing, 4)
                            .padding(.bottom, 4)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct VideoPlayerSheet: View {
    let video: LocalVideo
    @Binding var isPresented: Bool
    @State private var player: AVPlayer?
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let player = player {
                    VideoPlayer(player: player)
                        .onAppear {
                            player.play()
                        }
                        .onDisappear {
                            player.pause()
                        }
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
            }
            .navigationTitle("Dual POV Video")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Done") {
                    isPresented = false
                }
                .foregroundColor(.white)
            )
            .preferredColorScheme(.dark)
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
    
    private func setupPlayer() {
        player = AVPlayer(url: video.url)
        
        // Loop the video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in
            player?.seek(to: .zero)
            player?.play()
        }
    }
}

#Preview {
    CameraRollView()
} 