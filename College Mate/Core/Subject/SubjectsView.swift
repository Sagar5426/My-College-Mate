import SwiftUI
import SwiftData
import CoreData

struct SubjectsView: View {
    @Environment(\.modelContext) var modelContext
    @Query var subjects: [Subject]
    @State var isShowingAddSubject: Bool = false
    @State var isShowingProfileView = false
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                LazyVStack(spacing: 20, pinnedViews: [.sectionHeaders]) {
                    // Always show the header
                    Section(header:
                                GeometryReader { proxy in
                        HeaderView(
                            size: proxy.size,
                            title: "My Subjects",
                            icon: .asset("books_icon", size: 30),
                            isShowingProfileView: $isShowingProfileView
                        )
                    }
                        .frame(height: 60)
                    ) {
                        if subjects.isEmpty {
                            NoItemsView(isShowingAddSubject: $isShowingAddSubject)
                                .transition(AnyTransition.opacity.animation(.easeIn))
                        } else {
                            // Show list of subjects if available
                            ForEach(subjects, id: \.id) { subject in
                                NavigationLink {
                                    CardDetailView(subject: subject, modelContext: modelContext)
                                } label: {
                                    SubjectCardView(subject: subject)
                                        .contentShape(Rectangle())
                                }
                                .simultaneousGesture(TapGesture().onEnded {
                                    playHaptic(style: .light)
                                })
                            }
                            Spacer(minLength: 45)
                        }
                    }
                }
                .padding()
            }
            .background(LinearGradient.appBackground)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottomTrailing) {
                AddSubjectButton(isShowingAddSubject: $isShowingAddSubject)
            }
            .fullScreenCover(isPresented: $isShowingAddSubject) {
                AddSubjectView(isShowingAddSubjectView: $isShowingAddSubject)
            }
            .fullScreenCover(isPresented: $isShowingProfileView) {
                ProfileView(isShowingProfileView: $isShowingProfileView)
            }
        }
    }
    
    private func playHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}

struct AddSubjectButton: View {
    @Binding var isShowingAddSubject: Bool

    var body: some View {
        Button {
            isShowingAddSubject = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 60, height: 60)
                .background(
                    // This creates the frosted glass effect
                    .ultraThinMaterial, in: Circle()
                )
                .overlay(
                    // This adds a subtle "glass" border
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.4), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 5)
        }
        .padding()
        .sensoryFeedback(.impact(weight: .medium), trigger: isShowingAddSubject)
    }
}

// Preview
#Preview {
    SubjectsView()
}
