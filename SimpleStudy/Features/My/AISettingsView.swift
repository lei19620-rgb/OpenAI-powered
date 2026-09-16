import SwiftUI

struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var configuration = AIServiceConfiguration.saved
    @State private var key = ""
    @State private var hasSavedKey = false
    @State private var message: String?
    @State private var showsRemove = false

    var body: some View {
        Form {
            Section {
                AIIdentityHeader(title: "Your AI service", subtitle: "Connect directly to OpenAI. No backend required.")
            }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            Section {
                TextField("https://api.openai.com/v1", text: $configuration.baseURL)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("API base URL")
                TextField("Model ID", text: $configuration.model)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField(hasSavedKey ? "Saved; leave blank to keep" : "API Key", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("Output limit per request", selection: $configuration.outputLimit) {
                    Text("Short · 2000 tokens").tag(2000)
                    Text("Standard · 4000 tokens").tag(4000)
                    Text("Detailed · 8000 tokens").tag(8000)
                }
            } header: {
                Text("Connection")
            } footer: {
                Text("Uses the Responses API. Custom endpoints must support it. Keys are stored separately per endpoint in this device's Keychain.")
            }
            Section {
                Button("Save configuration") { save() }.fontWeight(.semibold)
                if hasSavedKey { Button("Remove this service's key", role: .destructive) { showsRemove = true } }
                if let message { Text(message).font(.subheadline).foregroundStyle(.secondary) }
            }
            Section("Privacy and usage") {
                Text("PDFs, notes, and assignments are never uploaded automatically. Review the text before each AI request. Dictionary lookup stays offline.")
                Text("API usage is billed separately from ChatGPT subscriptions. An output limit is not a spending cap. Configure account budgets and usage alerts too.")
                Text("Keys do not sync through iCloud. Configure each device separately. Generated study records follow your study-data sync settings.")
                Link("OpenAI data controls", destination: URL(string: "https://developers.openai.com/api/docs/guides/your-data")!)
            }.font(.subheadline)
        }
        .navigationTitle("AI service")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onAppear(perform: refreshKeyState)
        .onChange(of: configuration.baseURL) { _, _ in key = ""; refreshKeyState() }
        .confirmationDialog("Remove the key from this device? Your study records will be kept.", isPresented: $showsRemove, titleVisibility: .visible) {
            Button("Remove key", role: .destructive) {
                do { try AIKeychain.save("", host: configuration.credentialScope); hasSavedKey = false; key = "" }
                catch { message = error.localizedDescription }
            }
        }
    }

    private func refreshKeyState() {
        hasSavedKey = !((try? AIKeychain.read(host: configuration.credentialScope)) ?? "").isEmpty
    }
    private func save() {
        do {
            configuration.baseURL = configuration.credentialScope
            configuration.model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try configuration.endpoint()
            if !key.isEmpty { try AIKeychain.save(key.trimmingCharacters(in: .whitespacesAndNewlines), host: configuration.credentialScope) }
            try configuration.save()
            key = ""; refreshKeyState()
            message = "Saved on this device. Saving does not send a paid request."
        } catch { message = error.localizedDescription }
    }
}
