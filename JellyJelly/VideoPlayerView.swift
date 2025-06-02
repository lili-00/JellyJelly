import SwiftUI
import AVFoundation
import Combine

struct VideoPlayerView: View {
    let video: VideoModel
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var isMuted = true
    @State private var showControls = false
    @State private var timeObserver: Any?
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var controlsWorkItem: DispatchWorkItem?
    
    var body: some View {
        ZStack {
            // Video Player - Full Screen
            if let player = player {
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .ignoresSafeArea(.all)
                    .onTapGesture {
                        toggleControls()
                    }
            } else {
                // Loading placeholder
                Color.black
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.all)
                    .overlay(
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                    )
            }
            
            // Persistent Mute Button (Top Right)
            VStack {
                HStack {
                    Spacer()
                    
                    Button(action: {
                        toggleMute()
                    }) {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 60) // Account for status bar and safe area
                }
                
                Spacer()
            }
            
            // Custom Controls Overlay (Center)
            if showControls {
                VStack {
                    Spacer()
                    
                    HStack(spacing: 40) {
                        Button(action: {
                            restartVideo()
                        }) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        
                        Button(action: {
                            togglePlayPause()
                        }) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                                .padding(16)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                    }
                    
                    Spacer()
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: showControls)
            }
            
            // Video Info Overlay (Bottom)
            VStack {
                Spacer()
                videoInfoOverlay
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120) // Account for tab bar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanupPlayer()
        }
    }
    
    private var videoInfoOverlay: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: video.creatorAvatar)
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.gray.opacity(0.7))
                        .clipShape(Circle())
                    
                    Text(video.creator)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Text(video.title)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
            
            VStack(spacing: 4) {
                Text("\(VideoDataService().formatViewCount(video.viewCount)) views")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
                
                if duration > 0 {
                    Text(formatTime(duration))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
    }
    
    private func setupPlayer() {
        guard let url = URL(string: video.videoURL) else { return }
        
        player = AVPlayer(url: url)
        player?.isMuted = isMuted
        
        // Observe player status
        addTimeObserver()
        
        // Auto-play muted
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            playVideo()
        }
        
        // Get duration and handle end of video
        if let playerItem = player?.currentItem {
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { _ in
                restartVideo()
            }
        }
    }
    
    private func addTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = time.seconds
            if let item = player?.currentItem {
                duration = item.duration.seconds
            }
        }
    }
    
    private func cleanupPlayer() {
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        player?.pause()
        player = nil
        NotificationCenter.default.removeObserver(self)
    }
    
    private func togglePlayPause() {
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else {
            playVideo()
        }
    }
    
    private func playVideo() {
        player?.play()
        isPlaying = true
    }
    
    private func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }
    
    private func restartVideo() {
        player?.seek(to: .zero)
        playVideo()
    }
    
    private func toggleControls() {
        withAnimation {
            showControls.toggle()
        }
        
        if showControls {
            // Hide controls after 3 seconds
            controlsWorkItem?.cancel()
            controlsWorkItem = DispatchWorkItem {
                withAnimation {
                    showControls = false
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: controlsWorkItem!)
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// Custom VideoPlayer using UIViewRepresentable
struct VideoPlayer: UIViewRepresentable {
    let player: AVPlayer
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.black
        
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(playerLayer)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let playerLayer = uiView.layer.sublayers?.first as? AVPlayerLayer {
            DispatchQueue.main.async {
                playerLayer.frame = uiView.bounds
            }
        }
    }
} 