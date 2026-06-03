import Foundation


extension GooseAppModel {

  // One-shot guard: ensures health check runs at most once per app session.
  // Stored as a nonisolated var on a private wrapper to work around extension
  // stored-property restrictions; access is always on @MainActor.
  private static var _didRunHealthCheck = false

  func configureUploadService() {
    uploadService.onStatusUpdate = { [weak self] status in
      // Called on @MainActor via DispatchQueue.main.async in GooseUploadService
      self?.lastUploadAt = status.lastUploadTimestamp
      self?.pendingBatchCount = status.pendingBatchCount
      self?.lastSyncedCount = status.lastSyncedCount
    }
  }

  func triggerManualUpload() {
    let deviceID = ble.activeDeviceIdentifier ?? UUID()
    let sinceTimestamp = lastUploadAt ?? Date().addingTimeInterval(-24 * 3600)
    uploadService.upload(
      deviceID: deviceID,
      deviceType: "GOOSE",
      sinceTimestamp: sinceTimestamp
    )
  }

  func triggerUpload(for result: CaptureFrameWriteResult, deviceEvent: GooseNotificationEvent) {
    guard result.pass, result.errorDescription == nil else { return }
    // sinceTimestamp: 30 seconds ago covers the batch window generously
    let sinceTimestamp = Date().addingTimeInterval(-30)
    uploadService.upload(
      deviceID: deviceEvent.deviceID,
      deviceType: deviceEvent.rustDeviceType,
      sinceTimestamp: sinceTimestamp
    )
  }

  // Runs the GET /healthz check once per app session when upload is enabled
  // and a server URL is configured. Result is published via serverReachable.
  func triggerHealthCheckIfNeeded() {
    guard !GooseAppModel._didRunHealthCheck else { return }
    let uploadEnabled = UserDefaults.standard.bool(forKey: RemoteServerStorage.uploadEnabled)
    let serverURLString = UserDefaults.standard.string(forKey: RemoteServerStorage.serverURL) ?? ""
    guard uploadEnabled, !serverURLString.isEmpty else { return }
    GooseAppModel._didRunHealthCheck = true

    DispatchQueue.global(qos: .utility).async { [weak self] in
      guard let self else { return }
      guard let url = URL(string: serverURLString + "/healthz") else {
        Task { @MainActor in self.serverReachable = false }
        return
      }
      var request = URLRequest(url: url)
      request.timeoutInterval = 5
      let semaphore = DispatchSemaphore(value: 0)
      var isReachable = false
      var taskError: String?
      URLSession.shared.dataTask(with: request) { _, response, error in
        if let error {
          taskError = error.localizedDescription
        }
        isReachable = (response as? HTTPURLResponse)?.statusCode == 200
        semaphore.signal()
      }.resume()
      semaphore.wait()
      // Logging runs on the background queue (not inside the @Sendable dataTask closure)
      // so @MainActor-isolated ble can be safely captured here via Task.
      let logBody = taskError.map { "error=\($0)" } ?? "reachable=\(isReachable)"
      let logTitle = taskError != nil ? "healthz.error" : "healthz"
      Task { @MainActor [weak self] in
        self?.ble.record(level: .debug, source: "upload.health", title: logTitle, body: logBody)
      }

      Task { @MainActor in self.serverReachable = isReachable }
    }
  }
}
