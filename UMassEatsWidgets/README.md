# UMassEatsWidgets

Live Activity + Dynamic Island UI is ready in this folder. The new Xcode `project.xcproj` format couldn’t embed an app-extension target from tooling, so add it once in Xcode:

1. **File → New → Target → Widget Extension**
2. Product Name: `UMassEatsWidgets`
3. Enable **Include Live Activity**
4. Replace generated files with the sources in this folder
5. Add `UMassEatsShared` to the widget target membership (same `OrderActivityAttributes`)
6. Bundle ID: `edu.umass.eats.widgets`
7. Enable **Push Notifications** + **Live Activities** on the app target

Until the extension is added, `LiveActivityManager` still starts activities from the app; Lock Screen / Dynamic Island UI appears after the widget target is linked.
