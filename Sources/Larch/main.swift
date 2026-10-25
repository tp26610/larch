import AppKit

MainActor.assumeIsolated {
    let app = LarchApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = AppDelegate(smoke: CommandLine.arguments.contains("--smoke"))
    app.delegate = delegate
    app.run()
}
