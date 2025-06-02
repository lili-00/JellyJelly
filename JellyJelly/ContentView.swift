//
//  ContentView.swift
//  JellyJelly
//
//  Created by Li Li on 6/2/25.
//

import SwiftUI
import CoreData

struct ContentView: View {
    var body: some View {
        GeometryReader { geometry in
            TabView {
                FeedView()
                    .tabItem {
                        Image(systemName: "house.fill")
                        Text("Feed")
                    }
                    .tag(0)
                
                PlaceholderView(title: "Camera", icon: "camera.fill")
                    .tabItem {
                        Image(systemName: "camera.fill")
                        Text("Camera")
                    }
                    .tag(1)
                
                PlaceholderView(title: "Camera Roll", icon: "photo.on.rectangle")
                    .tabItem {
                        Image(systemName: "photo.on.rectangle")
                        Text("Camera Roll")
                    }
                    .tag(2)
            }
            .accentColor(.white)
        }
        .ignoresSafeArea(.all)
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
