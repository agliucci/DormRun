//
//  UMassEatsWidgetLiveActivity.swift
//  UMassEatsWidget
//
//  Created by Alessandro Liucci on 11/21/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct UMassEatsWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct UMassEatsWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: UMassEatsWidgetAttributes.self) { context in
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

extension UMassEatsWidgetAttributes {
    fileprivate static var preview: UMassEatsWidgetAttributes {
        UMassEatsWidgetAttributes(name: "World")
    }
}

extension UMassEatsWidgetAttributes.ContentState {
    fileprivate static var smiley: UMassEatsWidgetAttributes.ContentState {
        UMassEatsWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: UMassEatsWidgetAttributes.ContentState {
         UMassEatsWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: UMassEatsWidgetAttributes.preview) {
   UMassEatsWidgetLiveActivity()
} contentStates: {
    UMassEatsWidgetAttributes.ContentState.smiley
    UMassEatsWidgetAttributes.ContentState.starEyes
}
