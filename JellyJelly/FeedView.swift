import SwiftUI

struct FeedView: View {
    @StateObject private var videoDataService = VideoDataService()
    @State private var currentIndex = 0
    @State private var isRefreshing = false
    @State private var isLoadingMore = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea(.all)
                
                if videoDataService.videos.isEmpty {
                    // Loading state
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        
                        Text("Loading awesome videos...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                } else {
                    // Video Feed
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(videoDataService.videos.enumerated()), id: \.element.id) { index, video in
                                    VideoPlayerView(video: video)
                                        .frame(
                                            width: geometry.size.width,
                                            height: geometry.size.height
                                        )
                                        .clipped()
                                        .id(index)
                                        .onAppear {
                                            currentIndex = index
                                            
                                            // Load more videos when approaching the end
                                            if index >= videoDataService.videos.count - 2 && !isLoadingMore {
                                                loadMoreVideos()
                                            }
                                        }
                                }
                            }
                        }
                        .scrollTargetBehavior(.paging)
                        .ignoresSafeArea(.all)
                        .refreshable {
                            await refreshVideos()
                        }
                    }
                    
                    // Pull to refresh indicator
                    if isRefreshing {
                        VStack {
                            HStack {
                                Spacer()
                                
                                VStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(.white)
                                    
                                    Text("Refreshing...")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(12)
                                
                                Spacer()
                            }
                            
                            Spacer()
                        }
                        .padding(.top, 60)
                    }
                }
            }
        }
        .ignoresSafeArea(.all)
        .onAppear {
            // Preload videos if needed
            if videoDataService.videos.isEmpty {
                videoDataService.loadMockVideos()
            }
        }
    }
    
    private func loadMoreVideos() {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            videoDataService.loadMoreVideos()
            isLoadingMore = false
        }
    }
    
    @MainActor
    private func refreshVideos() async {
        isRefreshing = true
        
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        // Shuffle videos to simulate new content
        videoDataService.videos.shuffle()
        
        isRefreshing = false
    }
}

#Preview {
    FeedView()
} 