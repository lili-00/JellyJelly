//
//  ContentView.swift
//  JellyJelly
//
//  Created by Li Li on 6/2/25.
//

import SwiftUI
import CoreData

// Add the notification name extension
extension Notification.Name {
    static let videoRecorded = Notification.Name("videoRecorded")
}

struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView()
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Feed")
                }
                .tag(0)
            
            CameraView()
                .tabItem {
                    Image(systemName: "video.fill")
                    Text("Camera")
                }
                .tag(1)
            
            CameraRollView()
                .tabItem {
                    Image(systemName: "photo.stack.fill")
                    Text("Library")
                }
                .tag(2)
        }
        .accentColor(.green)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .videoRecorded)) { _ in
            // Navigate to Camera Roll when video is recorded
            selectedTab = 2
        }
    }
}

struct PlaceholderView: View {
    let title: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text(title)
                .font(.title)
                .foregroundColor(.gray)
            
            Text("Coming Soon")
                .font(.subheadline)
                .foregroundColor(.gray.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

#Preview {
    ContentView()
}
