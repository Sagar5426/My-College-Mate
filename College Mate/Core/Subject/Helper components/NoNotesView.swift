import SwiftUI

struct NoNotesView: View {
    let imageName: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundStyle(.white)
                
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.6))
                
            Text(message)
                .font(.body)
                .foregroundStyle(.gray.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding()
    }
}

#Preview {
    // 1. Wrap in GeometryReader to access the available size (proxy)
    GeometryReader { proxy in
        ZStack {
            Color.clear
            
            ScrollView {
                VStack {
                    // 2. Use proxy.size.height instead of UIScreen.main.bounds.height
                    Spacer(minLength: proxy.size.height / 4)
                    
                    NoNotesView(imageName: "doc.text.magnifyingglass",
                              title: "No Notes Added",
                              message: "Click on the add button to start adding notes.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // 3. Use proxy.size.height here as well
                    Spacer(minLength: proxy.size.height / 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea()
    }
}
