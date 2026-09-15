import SwiftUI

struct BotSheet: View {
    @ObservedObject var model: BrowserModel
    @StateObject private var vm = BotViewModel()
    @ObservedObject private var settings = BotSettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var usePage = true
    @State private var showSettings = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                messagesList
                if let e = vm.error {
                    Text(e).font(.system(size: 12)).foregroundColor(Theme.neonRed)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
                }
                inputBar
            }
            .background(Theme.black)
            .navigationTitle("j3nsontop bot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Picker("Backend", selection: $settings.backend) {
                            ForEach(BotBackend.allCases) { Text($0.label).tag($0) }
                        }
                        Button { vm.clear() } label: { Label("Clear chat", systemImage: "trash") }
                        Button { showSettings = true } label: { Label("Bot settings", systemImage: "gearshape") }
                    } label: {
                        HStack(spacing: 4) {
                            Text(settings.backend.label).font(.system(size: 13, weight: .semibold))
                            Image(systemName: "chevron.down").font(.system(size: 10))
                        }.foregroundColor(Theme.neonRed)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.tint(Theme.neonRed)
                }
            }
            .sheet(isPresented: $showSettings) { BotSettingsSheet() }
        }
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    if vm.messages.isEmpty {
                        Text("Ask about the page you're on, or anything.\nBackend: \(settings.backend.label)")
                            .multilineTextAlignment(.center)
                            .foregroundColor(Theme.textHint).font(.system(size: 13)).padding(.top, 40)
                    }
                    ForEach(vm.messages) { m in Bubble(message: m).id(m.id) }
                }.padding(12)
            }
            .onChange(of: vm.messages.last?.content) { _ in
                if let last = vm.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            Toggle(isOn: $usePage) {
                Text("Send current page as context").font(.system(size: 12)).foregroundColor(Theme.textHint)
            }.tint(Theme.neonRedDim).padding(.horizontal, 12)
            HStack(spacing: 8) {
                TextField("Message", text: $vm.input)
                    .foregroundColor(Theme.text)
                    .padding(10).background(Theme.cardGrey).cornerRadius(12)
                    .onSubmit(sendTapped)
                if vm.streaming {
                    Button { vm.stop() } label: {
                        Image(systemName: "stop.circle.fill").font(.system(size: 30)).foregroundColor(Theme.neonRed)
                    }
                } else {
                    Button(action: sendTapped) {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)).foregroundColor(Theme.neonRed)
                    }.disabled(vm.input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }.padding(.horizontal, 12).padding(.bottom, 8)
        }
    }

    private func sendTapped() {
        if usePage {
            model.capturePageText { ctx in vm.send(pageContext: ctx) }
        } else {
            vm.send(pageContext: nil)
        }
    }
}

struct Bubble: View {
    let message: ChatMessage
    var isUser: Bool { message.role == "user" }
    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(message.content.isEmpty ? "…" : message.content)
                .foregroundColor(isUser ? .black : Theme.text)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(isUser ? Theme.neonRed : Theme.cardGrey)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 40) }
        }
    }
}

struct BotSettingsSheet: View {
    @ObservedObject private var settings = BotSettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var anthropicKey = ""
    @State private var openaiKey = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Backend").foregroundColor(Theme.neonRed)) {
                    Picker("Backend", selection: $settings.backend) {
                        ForEach(BotBackend.allCases) { Text($0.label).tag($0) }
                    }.foregroundColor(Theme.text).listRowBackground(Theme.darkGrey)
                }
                Section(header: Text("Ollama (your PC, over LAN)").foregroundColor(Theme.neonRed)) {
                    field("Base URL", text: $settings.ollamaBase)
                    field("Model", text: $settings.ollamaModel)
                }
                Section(header: Text("Claude").foregroundColor(Theme.neonRed)) {
                    field("Model", text: $settings.claudeModel)
                    secure("Anthropic API key", text: $anthropicKey, account: "anthropic")
                }
                Section(header: Text("OpenAI").foregroundColor(Theme.neonRed)) {
                    field("Model", text: $settings.openaiModel)
                    secure("OpenAI API key", text: $openaiKey, account: "openai")
                }
                Section {
                    Text("Keys are stored in the iOS Keychain on this device only. There is no bundled key.")
                        .font(.system(size: 12)).foregroundColor(Theme.textHint).listRowBackground(Theme.darkGrey)
                }
            }
            .scrollContentBackgroundHiddenCompat().background(Theme.black)
            .navigationTitle("Bot settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() }.tint(Theme.neonRed) }
            }
            .onAppear {
                anthropicKey = Keychain.has("anthropic") ? "••••••••" : ""
                openaiKey = Keychain.has("openai") ? "••••••••" : ""
            }
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        TextField(label, text: text)
            .foregroundColor(Theme.text).autocorrectionDisabled(true)
            .textInputAutocapitalization(.never).listRowBackground(Theme.darkGrey)
    }

    private func secure(_ label: String, text: Binding<String>, account: String) -> some View {
        HStack {
            SecureField(label, text: text)
                .foregroundColor(Theme.text).autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
            Button("Save") {
                if text.wrappedValue != "••••••••" && !text.wrappedValue.isEmpty {
                    Keychain.set(text.wrappedValue, for: account)
                    text.wrappedValue = "••••••••"
                }
            }.font(.system(size: 12)).tint(Theme.neonRed)
        }.listRowBackground(Theme.darkGrey)
    }
}
