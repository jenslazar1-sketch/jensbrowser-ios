import SwiftUI

// MARK: - User mods

struct ModsSheet: View {
    @ObservedObject private var store = UserScriptsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editing: UserMod?

    var body: some View {
        NavigationView {
            List {
                if store.mods.isEmpty {
                    Text("Attach CSS/JS to a host glob. Injected when a page finishes loading.")
                        .foregroundColor(Theme.textHint).font(.system(size: 13))
                        .listRowBackground(Theme.darkGrey)
                }
                ForEach(store.mods) { mod in
                    HStack {
                        Button { editing = mod } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mod.name).foregroundColor(Theme.text)
                                Text(mod.hostGlob).font(.system(size: 11)).foregroundColor(Theme.textHint)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { mod.enabled },
                            set: { var m = mod; m.enabled = $0; store.upsert(m) }))
                            .labelsHidden().tint(Theme.neonRed)
                    }.listRowBackground(Theme.darkGrey)
                }
                .onDelete { idx in idx.map { store.mods[$0] }.forEach { store.delete($0) } }
            }
            .scrollContentBackgroundHiddenCompat().background(Theme.black)
            .navigationTitle("Mods")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { editing = UserMod() } label: { Image(systemName: "plus") }.tint(Theme.neonRed)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }.tint(Theme.neonRed)
                }
            }
            .sheet(item: $editing) { mod in ModEditor(mod: mod) }
        }
    }
}

struct ModEditor: View {
    @State var mod: UserMod
    @Environment(\.dismiss) private var dismiss
    private let store = UserScriptsStore.shared

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Name", text: $mod.name).foregroundColor(Theme.text)
                        .listRowBackground(Theme.darkGrey)
                    TextField("Host glob (e.g. *.example.com or *)", text: $mod.hostGlob)
                        .foregroundColor(Theme.text).autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never).listRowBackground(Theme.darkGrey)
                    Toggle("Enabled", isOn: $mod.enabled).tint(Theme.neonRed)
                        .foregroundColor(Theme.text).listRowBackground(Theme.darkGrey)
                }
                Section(header: Text("CSS").foregroundColor(Theme.neonRed)) {
                    TextEditor(text: $mod.css).frame(minHeight: 100).foregroundColor(Theme.text)
                        .scrollContentBackgroundHiddenCompat().listRowBackground(Theme.darkGrey)
                }
                Section(header: Text("JavaScript").foregroundColor(Theme.neonRed)) {
                    TextEditor(text: $mod.js).frame(minHeight: 120).foregroundColor(Theme.text)
                        .autocorrectionDisabled(true).textInputAutocapitalization(.never)
                        .scrollContentBackgroundHiddenCompat().listRowBackground(Theme.darkGrey)
                }
            }
            .scrollContentBackgroundHiddenCompat().background(Theme.black)
            .navigationTitle("Edit mod")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { store.upsert(mod); dismiss() }.tint(Theme.neonRed)
                }
            }
        }
    }
}

// MARK: - Dev console

struct DevConsoleSheet: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject private var console: ConsoleLog
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var js = ""
    @State private var jsResult = ""
    @State private var info = ""

    init(model: BrowserModel) {
        _model = ObservedObject(wrappedValue: model)
        _console = ObservedObject(wrappedValue: model.consoleLog)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Console").tag(0); Text("Run JS").tag(1); Text("Info").tag(2)
                }.pickerStyle(.segmented).padding(8)

                if tab == 0 { consoleTab }
                else if tab == 1 { jsTab }
                else { infoTab }
            }
            .background(Theme.black)
            .navigationTitle("Dev console")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() }.tint(Theme.neonRed) }
                ToolbarItem(placement: .navigationBarLeading) {
                    if tab == 0 { Button("Clear") { console.clear() }.tint(Theme.neonRed) }
                }
            }
            .onAppear { if tab == 2 { loadInfo() } }
        }
    }

    private var consoleTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(console.entries.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.system(size: 12, design: .monospaced))
                        .foregroundColor(line.hasPrefix("[error]") ? Theme.neonRed :
                                         (line.hasPrefix("[warn]") ? .orange : Theme.text))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(10)
        }.background(Theme.black)
    }

    private var jsTab: some View {
        VStack(spacing: 8) {
            TextEditor(text: $js).frame(height: 120).foregroundColor(Theme.text)
                .autocorrectionDisabled(true).textInputAutocapitalization(.never)
                .scrollContentBackgroundHiddenCompat().background(Theme.cardGrey).cornerRadius(8)
            Button("Run on active tab") { model.runJS(js) { jsResult = $0 } }
                .tint(Theme.neonRed)
            ScrollView {
                Text(jsResult).font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.text).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(10)
    }

    private var infoTab: some View {
        ScrollView {
            Text(info).font(.system(size: 12, design: .monospaced))
                .foregroundColor(Theme.text).frame(maxWidth: .infinity, alignment: .leading).padding(10)
        }.onAppear { loadInfo() }
    }

    private func loadInfo() { model.pageInfo { info = $0 } }
}

// MARK: - Block rules

struct BlockRulesSheet: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("Block trackers & ads", isOn: Binding(
                        get: { store.blockingEnabled },
                        set: { store.blockingEnabled = $0; store.save(); model.compileBlocking() }))
                        .tint(Theme.neonRed).foregroundColor(Theme.text).listRowBackground(Theme.darkGrey)
                } footer: {
                    Text("\(ContentBlocking.builtinTrackers.count) built-in tracker domains + your list below. iOS blocks via compiled rules, so there is no per-request network log.")
                        .foregroundColor(Theme.textHint)
                }
                Section(header: Text("Extra domains to block").foregroundColor(Theme.neonRed)) {
                    TextEditor(text: Binding(
                        get: { store.blockRulesText }, set: { store.blockRulesText = $0 }))
                        .frame(minHeight: 140).foregroundColor(Theme.text)
                        .autocorrectionDisabled(true).textInputAutocapitalization(.never)
                        .scrollContentBackgroundHiddenCompat().listRowBackground(Theme.darkGrey)
                }
            }
            .scrollContentBackgroundHiddenCompat().background(Theme.black)
            .navigationTitle("Block rules")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") { store.save(); model.compileBlocking(); dismiss() }.tint(Theme.neonRed)
                }
            }
        }
    }
}

// MARK: - Find in page bar

struct FindBar: View {
    @ObservedObject var model: BrowserModel
    @Binding var query: String
    @Binding var shown: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(Theme.textHint)
            TextField("Find in page", text: $query)
                .foregroundColor(Theme.text).submitLabel(.search)
                .onSubmit { model.findInPage(query) }
            Button { model.findInPage(query) } label: {
                Image(systemName: "chevron.down").foregroundColor(Theme.neonRed)
            }
            Button { shown = false; query = "" } label: {
                Image(systemName: "xmark").foregroundColor(Theme.textHint)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.cardGrey).clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 10)
    }
}
