import Foundation

struct VideoModel: Identifiable, Codable {
    let id = UUID()
    let videoURL: String
    let thumbnailURL: String
    let title: String
    let creator: String
    let creatorAvatar: String
    let duration: TimeInterval
    let viewCount: Int
    let isLiked: Bool
    
    init(videoURL: String, thumbnailURL: String, title: String, creator: String, creatorAvatar: String, duration: TimeInterval, viewCount: Int, isLiked: Bool = false) {
        self.videoURL = videoURL
        self.thumbnailURL = thumbnailURL
        self.title = title
        self.creator = creator
        self.creatorAvatar = creatorAvatar
        self.duration = duration
        self.viewCount = viewCount
        self.isLiked = isLiked
    }
}

// Mock data for demonstration
class VideoDataService: ObservableObject {
    @Published var videos: [VideoModel] = []
    private var allSampleVideos: [VideoModel] = []
    
    init() {
        setupSampleVideos()
        loadMockVideos()
    }
    
    private func setupSampleVideos() {
        allSampleVideos = [
            VideoModel(
                videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
                thumbnailURL: "https://i.ytimg.com/vi/YE7VzlLtp-4/maxresdefault.jpg",
                title: "Amazing Nature Views",
                creator: "@naturelover",
                creatorAvatar: "person.circle.fill",
                duration: 60.0,
                viewCount: 1200000
            ),
            VideoModel(
                videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4",
                thumbnailURL: "https://i.ytimg.com/vi/TdIRrmNN_CQ/maxresdefault.jpg",
                title: "Creative Animation",
                creator: "@animator",
                creatorAvatar: "person.circle.fill",
                duration: 45.0,
                viewCount: 850000
            ),
            VideoModel(
                videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
                thumbnailURL: "https://i.ytimg.com/vi/rdaHFHVNOtQ/maxresdefault.jpg",
                title: "Epic Adventure",
                creator: "@adventurer",
                creatorAvatar: "person.circle.fill",
                duration: 30.0,
                viewCount: 2100000
            ),
            VideoModel(
                videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4",
                thumbnailURL: "https://i.ytimg.com/vi/2Gg6Seob7bg/maxresdefault.jpg",
                title: "Travel Goals",
                creator: "@traveler",
                creatorAvatar: "person.circle.fill",
                duration: 75.0,
                viewCount: 950000
            ),
            VideoModel(
                videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4",
                thumbnailURL: "https://i.ytimg.com/vi/rN6nlNC9WQA/maxresdefault.jpg",
                title: "Fun Times",
                creator: "@comedian",
                creatorAvatar: "person.circle.fill",
                duration: 40.0,
                viewCount: 1800000
            ),
            VideoModel(
                videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4",
                thumbnailURL: "https://i.ytimg.com/vi/vQ-xKlkzLuE/maxresdefault.jpg",
                title: "Road Trip Vibes",
                creator: "@roadtripper",
                creatorAvatar: "person.circle.fill",
                duration: 55.0,
                viewCount: 1350000
            ),
            VideoModel(
                videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4",
                thumbnailURL: "https://i.ytimg.com/vi/J_8mdH20qTQ/maxresdefault.jpg",
                title: "Drama Scene",
                creator: "@filmmaker",
                creatorAvatar: "person.circle.fill",
                duration: 35.0,
                viewCount: 680000
            ),
            VideoModel(
                videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4",
                thumbnailURL: "https://i.ytimg.com/vi/eRsGyueVLvQ/maxresdefault.jpg",
                title: "Fantasy Adventure",
                creator: "@fantasyfan",
                creatorAvatar: "person.circle.fill",
                duration: 90.0,
                viewCount: 3200000
            )
        ]
    }
    
    func loadMockVideos() {
        // Start with first 3 videos
        videos = Array(allSampleVideos.prefix(3))
    }
    
    func loadMoreVideos() {
        // Add more videos by cycling through the sample videos with variations
        let baseVideos = allSampleVideos.shuffled()
        var newVideos: [VideoModel] = []
        
        for video in baseVideos.prefix(3) {
            let newVideo = VideoModel(
                videoURL: video.videoURL,
                thumbnailURL: video.thumbnailURL,
                title: video.title,
                creator: video.creator,
                creatorAvatar: video.creatorAvatar,
                duration: video.duration,
                viewCount: Int.random(in: 500000...5000000) // Randomize view count
            )
            newVideos.append(newVideo)
        }
        
        videos.append(contentsOf: newVideos)
    }
    
    func formatViewCount(_ count: Int) -> String {
        if count >= 1000000 {
            return String(format: "%.1fM", Double(count) / 1000000.0)
        } else if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        } else {
            return "\(count)"
        }
    }
} 