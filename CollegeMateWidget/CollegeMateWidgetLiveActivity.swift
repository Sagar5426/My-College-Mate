//
//  CollegeMateWidgetLiveActivity.swift
//  CollegeMateWidget
//
//  Created by Sagar Jangra on 29/01/2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct CollegeMateWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct CollegeMateWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CollegeMateWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension CollegeMateWidgetAttributes {
    fileprivate static var preview: CollegeMateWidgetAttributes {
        CollegeMateWidgetAttributes(name: "World")
    }
}

extension CollegeMateWidgetAttributes.ContentState {
    fileprivate static var smiley: CollegeMateWidgetAttributes.ContentState {
        CollegeMateWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: CollegeMateWidgetAttributes.ContentState {
         CollegeMateWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: CollegeMateWidgetAttributes.preview) {
   CollegeMateWidgetLiveActivity()
} contentStates: {
    CollegeMateWidgetAttributes.ContentState.smiley
    CollegeMateWidgetAttributes.ContentState.starEyes
}
