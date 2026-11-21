//
//  UMassEatsWidgetBundle.swift
//  UMassEatsWidget
//
//  Created by Alessandro Liucci on 11/21/26.
//

import WidgetKit
import SwiftUI

@main
struct UMassEatsWidgetBundle: WidgetBundle {
    var body: some Widget {
        UMassEatsWidget()
        UMassEatsWidgetControl()
        UMassEatsWidgetLiveActivity()
    }
}
