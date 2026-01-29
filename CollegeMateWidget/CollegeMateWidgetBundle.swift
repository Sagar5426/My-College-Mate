//
//  CollegeMateWidgetBundle.swift
//  CollegeMateWidget
//
//  Created by Sagar Jangra on 29/01/2026.
//

import WidgetKit
import SwiftUI

@main
struct CollegeMateWidgetBundle: WidgetBundle {
    var body: some Widget {
        CollegeMateWidget()
        CollegeMateWidgetControl()
        CollegeMateWidgetLiveActivity()
        ClassActivityWidget()
    }
}
