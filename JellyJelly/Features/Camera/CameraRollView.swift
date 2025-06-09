import SwiftUI
import AVKit

struct CameraRollView: View {
    @StateObject private var videoStorage = LocalVideoStorage.shared
    @State private var selectedVideo: LocalVideo?
    @State private var showingVideoPlayer = false
    @State private var isEditMode = false
    @State private var videoToDelete: LocalVideo?
    @State private var showingDeleteConfirmation = false
    
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
                                VideoThumbnailView(video: video, isEditMode: isEditMode) {
                                    selectedVideo = video
                                    showingVideoPlayer = true
                                } onDelete: {
                                    videoToDelete = video
                                    showingDeleteConfirmation = true
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.top, 10)
                    }
                }
            }
            .navigationTitle("Camera Roll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !videoStorage.videos.isEmpty {
                        Button(isEditMode ? "Done" : "Edit") {
                            isEditMode.toggle()
                        }
                        .foregroundColor(.white)
                    }
                }
            }
            .preferredColorScheme(.dark)
            .alert(isPresented: $showingDeleteConfirmation) {
                Alert(
                    title: Text("Delete Video"),
                    message: Text("Are you sure you want to delete this video? This action cannot be undone."),
                    primaryButton: .destructive(Text("Delete")) {
                        if let video = videoToDelete {
                            deleteVideo(video)
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .sheet(isPresented: $showingVideoPlayer) {
            if let video = selectedVideo {
                VideoPlayerSheet(video: video, isPresented: $showingVideoPlayer) {
                    videoToDelete = video
                    showingDeleteConfirmation = true
                    showingVideoPlayer = false
                }
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
    
    private func deleteVideo(_ video: LocalVideo) {
        videoStorage.deleteVideo(video)
        videoToDelete = nil
        
        // If we're deleting the last video, exit edit mode
        if videoStorage.videos.isEmpty {
            isEditMode = false
        }
    }
}

struct VideoThumbnailView: View {
    let video: LocalVideo
    let isEditMode: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        ZStack {
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
                    
                    // Play button overlay (only when not in edit mode)
                    if !isEditMode {
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .offset(x: 2) // Slight offset to center the play icon
                            )
                    }
                    
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
            .disabled(isEditMode)
            
            // Delete button (only visible in edit mode)
            if isEditMode {
                VStack {
                    HStack {
                        Button(action: onDelete) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.red)
                                .background(Circle().fill(Color.white))
                                .shadow(radius: 2)
                        }
                        .padding(8)
                        
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
    }
}

struct VideoPlayerSheet: View {
    let video: LocalVideo
    @Binding var isPresented: Bool
    @State private var player: AVPlayer?
    var onDelete: () -> Void
    
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        isPresented = false
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
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
