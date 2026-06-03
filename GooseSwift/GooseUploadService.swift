import Foundation
import OSLog

private let logger = Logger(subsystem: "com.goose.swift", category: "upload")

struct GooseUploadStatus {
  let lastUploadTimestamp: Date?
  let pendingBatchCount: Int
  let lastSyncedCount: Int?
}

final class GooseUploadService: @unchecked Sendable {
  private let uploadQueue = DispatchQueue(label: "com.goose.swift.upload", qos: .utility)
  private let rust = GooseRustBridge()
  private let databasePath: String
  private let session: URLSession

  private var lastUploadTimestamp: Date?
  private var pendingBatchCount: Int = 0
  private var lastSyncedCount: Int?

  var onStatusUpdate: (@MainActor (GooseUploadStatus) -> Void)?

  init(databasePath: String) {
    self.databasePath = databasePath
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 15
    self.session = URLSession(configuration: config)
  }

  func upload(deviceID: UUID, deviceType: String, sinceTimestamp: Date) {
    uploadQueue.async { [weak self] in
      guard let self else { return }
      self.pendingBatchCount += 1
      self.performUpload(deviceID: deviceID, deviceType: deviceType, sinceTimestamp: sinceTimestamp)
    }
  }

  private func performUpload(deviceID: UUID, deviceType: String, sinceTimestamp: Date) {
    // Guard: upload only when enabled, URL configured, and token present
    guard UserDefaults.standard.bool(forKey: RemoteServerStorage.uploadEnabled) else {
      pendingBatchCount = max(0, pendingBatchCount - 1)
      return
    }
    let rawURL = UserDefaults.standard.string(forKey: RemoteServerStorage.serverURL) ?? ""
    guard !rawURL.isEmpty, let baseURL = URL(string: rawURL) else {
      pendingBatchCount = max(0, pendingBatchCount - 1)
      return
    }
    guard let token = (try? RemoteServerKeychain.loadToken()) ?? nil, !token.isEmpty else {
      pendingBatchCount = max(0, pendingBatchCount - 1)
      return
    }

    // Fetch recent decoded streams from Rust bridge (runs on uploadQueue — never @MainActor)
    let streamsResult: [String: Any]
    do {
      streamsResult = try rust.request(
        method: "upload.get_recent_decoded_streams",
        args: [
          "database_path": databasePath,
          "device_id": deviceID.uuidString,
          "since_ts": sinceTimestamp.timeIntervalSince1970,
        ]
      )
    } catch {
      logger.debug("upload.get_recent_decoded_streams failed: \(error)")
      pendingBatchCount = max(0, pendingBatchCount - 1)
      return
    }

    // Skip empty batches to avoid unnecessary POST requests
    let hr = streamsResult["hr"] as? [Any] ?? []
    let rr = streamsResult["rr"] as? [Any] ?? []
    let events = streamsResult["events"] as? [Any] ?? []
    let battery = streamsResult["battery"] as? [Any] ?? []
    let spo2 = streamsResult["spo2"] as? [Any] ?? []
    let skinTemp = streamsResult["skin_temp"] as? [Any] ?? []
    let resp = streamsResult["resp"] as? [Any] ?? []
    let gravity = streamsResult["gravity"] as? [Any] ?? []

    let hasData = !hr.isEmpty || !rr.isEmpty || !events.isEmpty || !battery.isEmpty
      || !spo2.isEmpty || !skinTemp.isEmpty || !resp.isEmpty || !gravity.isEmpty
    guard hasData else {
      pendingBatchCount = max(0, pendingBatchCount - 1)
      return
    }

    // Build payload matching DecodedBatch server contract
    let deviceGeneration = deviceType == "GEN4" ? "4.0" : "5.0"
    let streams: [String: Any] = [
      "hr": hr,
      "rr": rr,
      "events": events,
      "battery": battery,
      "spo2": spo2,
      "skin_temp": skinTemp,
      "resp": resp,
      "gravity": gravity,
    ]
    let payload: [String: Any] = [
      "device": [
        "id": deviceID.uuidString,
        "mac": NSNull(),
        "name": NSNull(),
      ],
      "streams": streams,
      "device_generation": deviceGeneration,
    ]

    guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
      pendingBatchCount = max(0, pendingBatchCount - 1)
      return
    }

    // Build URLRequest
    var request = URLRequest(url: baseURL.appendingPathComponent("v1/ingest-decoded"))
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    // Retry loop: 3 attempts with backoff 1s/2s/4s
    let delays: [TimeInterval] = [1, 2, 4]
    var uploadSucceeded = false
    var syncedCount: Int?
    for attempt in 0..<3 {
      if attempt > 0 {
        Thread.sleep(forTimeInterval: delays[attempt - 1])
      }
      if let count = performRequest(request) {
        uploadSucceeded = true
        syncedCount = count
        break
      }
    }

    if uploadSucceeded {
      lastUploadTimestamp = Date()
      lastSyncedCount = syncedCount
    } else {
      logger.debug("upload failed after 3 attempts — discarding batch silently")
    }
    pendingBatchCount = max(0, pendingBatchCount - 1)
    publishStatus()
  }

  // Returns the total upserted record count on success, nil on failure.
  private func performRequest(_ request: URLRequest) -> Int? {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Int?
    session.dataTask(with: request) { data, response, error in
      if let error {
        logger.debug("upload request error: \(error)")
      } else if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
        if let data,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let upserted = json["upserted"] as? [String: Int] {
          result = upserted.values.reduce(0, +)
        } else {
          result = 0
        }
      } else if let http = response as? HTTPURLResponse {
        logger.debug("upload server error: \(http.statusCode)")
      }
      semaphore.signal()
    }.resume()
    semaphore.wait()
    return result
  }

  private func publishStatus() {
    let status = GooseUploadStatus(
      lastUploadTimestamp: lastUploadTimestamp,
      pendingBatchCount: pendingBatchCount,
      lastSyncedCount: lastSyncedCount
    )
    DispatchQueue.main.async { [weak self] in
      self?.onStatusUpdate?(status)
    }
  }
}
