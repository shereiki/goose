import Foundation
import SwiftUI
import UIKit

@MainActor
final class MoreRemoteServerViewModel: ObservableObject {
  @Published var serverURL: String
  @Published var bearerToken: String
  @Published var uploadEnabled: Bool
  @Published var urlValidationError: String?
  @Published var saveSuccess: Bool = false

  init() {
    serverURL = UserDefaults.standard.string(forKey: RemoteServerStorage.serverURL) ?? ""
    bearerToken = (try? RemoteServerKeychain.loadToken()) ?? ""
    uploadEnabled = UserDefaults.standard.bool(forKey: RemoteServerStorage.uploadEnabled)
  }

  func save() {
    guard RemoteServerURLValidator.validate(serverURL) else {
      urlValidationError = "URL inválida. Use https://hostname (não IPs numéricos)."
      return
    }
    urlValidationError = nil
    UserDefaults.standard.set(serverURL, forKey: RemoteServerStorage.serverURL)
    UserDefaults.standard.set(uploadEnabled, forKey: RemoteServerStorage.uploadEnabled)
    try? RemoteServerKeychain.saveToken(bearerToken)
    saveSuccess = true
  }
}

struct MoreRemoteServerView: View {
  @StateObject private var vm = MoreRemoteServerViewModel()
  @EnvironmentObject private var model: GooseAppModel

  private var uploadIsActive: Bool {
    vm.uploadEnabled && !vm.serverURL.isEmpty
  }

  var body: some View {
    Form {
      Section("Server") {
        TextField("https://meu-servidor.local", text: $vm.serverURL)
          .keyboardType(.URL)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
        if let error = vm.urlValidationError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }

      Section("Authentication") {
        SecureField("Bearer token (API key)", text: $vm.bearerToken)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
      }

      Section("Upload") {
        Toggle("Enable Upload", isOn: $vm.uploadEnabled)
      }

      if uploadIsActive {
        Section("Status") {
          // Row 1: Server reachability
          Label {
            switch model.serverReachable {
            case .none:
              Text("A verificar...").foregroundStyle(.secondary)
            case .some(true):
              Text("Servidor acessível").foregroundStyle(.green)
            case .some(false):
              Text("Servidor inacessível").foregroundStyle(.red)
            }
          } icon: {
            switch model.serverReachable {
            case .none:
              ProgressView().scaleEffect(0.7)
            case .some(true):
              Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .some(false):
              Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            }
          }

          // Row 2: Last upload timestamp
          if let lastUpload = model.lastUploadAt {
            LabeledContent("Último upload") {
              Text(RelativeDateTimeFormatter().localizedString(for: lastUpload, relativeTo: Date()))
                .foregroundStyle(.secondary)
            }
          } else {
            LabeledContent("Último upload") {
              Text("Nunca").foregroundStyle(.secondary)
            }
          }

          // Row 3: Pending batch count
          LabeledContent("Batches pendentes") {
            Text("\(model.pendingBatchCount)")
              .foregroundStyle(model.pendingBatchCount > 0 ? .orange : .secondary)
          }
        }
      }

      Section {
        Button("Save") {
          vm.save()
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
      }
    }
    .navigationTitle("Remote Server")
    .navigationBarTitleDisplayMode(.inline)
    .listStyle(.insetGrouped)
    .gooseListBackground()
    .alert("Configurações guardadas", isPresented: $vm.saveSuccess) {
      Button("OK") {}
    }
  }
}

// MARK: - Previews

#Preview("Status — A verificar") {
  NavigationStack {
    MoreRemoteServerView()
  }
  .environmentObject({
    let m = GooseAppModel()
    m.serverReachable = nil
    m.lastUploadAt = nil
    m.pendingBatchCount = 0
    return m
  }())
}

#Preview("Status — Acessível") {
  NavigationStack {
    MoreRemoteServerView()
  }
  .environmentObject({
    let m = GooseAppModel()
    m.serverReachable = true
    m.lastUploadAt = Date().addingTimeInterval(-120)
    m.pendingBatchCount = 0
    return m
  }())
}

#Preview("Status — Inacessível") {
  NavigationStack {
    MoreRemoteServerView()
  }
  .environmentObject({
    let m = GooseAppModel()
    m.serverReachable = false
    m.lastUploadAt = nil
    m.pendingBatchCount = 2
    return m
  }())
}
