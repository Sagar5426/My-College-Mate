//
//  LottieHelperView.swift
//  My College Mate
//
//  Created by Sagar Jangra on 26/01/2026.
//

import SwiftUI
import Lottie

struct LottieHelperView: View {
    var fileName: String = "Beach.json"
    var contentMode: UIView.ContentMode = .scaleAspectFit
    var playLoopMode: LottieLoopMode = .loop
    var size: CGSize = .init(width: 120, height: 120)
    var animationScale: CGFloat = 1.0
    var onAnimationDidFinish: (() -> Void)? = nil

    var body: some View {
        LottieView(animation: .named(fileName))
            .configure { lottieAnimationView in
                lottieAnimationView.contentMode = contentMode
                lottieAnimationView.transform = CGAffineTransform(scaleX: animationScale,
                                                                   y: animationScale)
            }
            .playbackMode(.playing(.toProgress(1, loopMode: playLoopMode)))
            .animationDidFinish { _ in
                onAnimationDidFinish?()
            }
            .frame(width: size.width, height: size.height)
    }
}
