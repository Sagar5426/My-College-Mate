//
//  View+Extension.swift
//  Expense Tracker - Sagar
//
//  Created by Sagar Jangra on 29/08/2024.
//

import SwiftUI

// MARK: - Header Icon Type
enum HeaderIcon {
    case emoji(String)
    case asset(String)     // SVG / PDF from Assets
    case system(String)    // SF Symbols
}

extension View {

    // MARK: - Spacing Helpers
    @ViewBuilder
    func hSpacing(_ alignment: Alignment = .center) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    @ViewBuilder
    func vSpacing(_ alignment: Alignment = .center) -> some View {
        self
            .frame(maxHeight: .infinity, alignment: alignment)
    }

    // MARK: - Safe Area Helper
    @available(iOSApplicationExtension, unavailable)
    var safeArea: UIEdgeInsets {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return windowScene.keyWindow?.safeAreaInsets ?? .zero
        }
        return .zero
    }

    // MARK: - Date Formatter
    func format(date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    // MARK: - EXISTING Header View (UNCHANGED ✅)
    @ViewBuilder
    func HeaderView(
        size: CGSize,
        title: String,
        isShowingProfileView: Binding<Bool>
    ) -> some View {

        let safeArea = self.safeArea

        HStack(spacing: 10) {
            Text(title)
                .font(.title.bold())

            Spacer(minLength: 0)

            profileIcon(isShowingProfileView)
        }
        .padding(.bottom, 10)
        .background {
            headerBackground(safeArea: safeArea)
        }
    }

    // MARK: - NEW Header View (Icon Support)
    @ViewBuilder
    func HeaderView(
        size: CGSize,
        title: String,
        icon: HeaderIcon,
        isShowingProfileView: Binding<Bool>
    ) -> some View {

        let safeArea = self.safeArea

        HStack(spacing: 10) {

            HStack(spacing: 8) {
                Text(title)
                    .font(.title.bold())

                headerIconView(icon)
            }

            Spacer(minLength: 0)

            profileIcon(isShowingProfileView)
        }
        .padding(.bottom, 10)
        .background {
            headerBackground(safeArea: safeArea)
        }
    }

    // MARK: - Header Icon Renderer
    @ViewBuilder
    private func headerIconView(_ icon: HeaderIcon) -> some View {
        switch icon {

        case .emoji(let value):
            Text(value)

        case .asset(let name):
            let image = Image(name)
            image
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .foregroundColor(.blue)

        case .system(let name):
            Image(systemName: name)
                .font(.title2)
        }
    }


    // MARK: - Profile Icon
    @ViewBuilder
    private func profileIcon(_ isShowingProfileView: Binding<Bool>) -> some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 45, height: 45)
            .foregroundStyle(.white)
            .background(
                Circle()
                    .fill(Color.blue.gradient)
                    .frame(width: 55, height: 55)
            )
            .shadow(radius: 5)
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isShowingProfileView.wrappedValue = true
            }
    }

    // MARK: - Header Background
    @ViewBuilder
    private func headerBackground(safeArea: UIEdgeInsets) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.ultraThinMaterial)

            Divider()
        }
        .visualEffect { content, proxy in
            content
                .opacity(headerBGOpacity(proxy, safeArea: safeArea))
        }
        .padding(.horizontal, -15)
        .padding(.top, -(safeArea.top + 15))
    }

    // MARK: - Header Effects
    nonisolated func headerBGOpacity(
        _ proxy: GeometryProxy,
        safeArea: UIEdgeInsets
    ) -> CGFloat {

        let minY = proxy.frame(in: .scrollView).minY + safeArea.top
        return minY > 0 ? 0 : (-minY / 15)
    }

    nonisolated func headerScale(
        _ size: CGSize,
        proxy: GeometryProxy,
        safeArea: UIEdgeInsets
    ) -> CGFloat {

        let minY = proxy.frame(in: .scrollView).minY
        let screenHeight = size.height

        let progress = minY / screenHeight
        let scale = min(max(progress, 0), 1) * 0.4

        return 1 + scale
    }
}
