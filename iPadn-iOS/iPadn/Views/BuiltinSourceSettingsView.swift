// 内置软件源设置：修改地址、保存、开/关。
// 按钮：修改（进入编辑）/ 保存 / 开 / 关。

import SwiftUI

struct BuiltinSourceSettingsView: View {
    @EnvironmentObject private var store: ToolStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var draft = ""
    @State private var savedTip = false

    private var enabled: Bool { store.settings.builtinSourceEnabled }
    private var currentURL: String { store.settings.builtinSourceURL }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if editing {
                        TextField("内置软件源地址", text: $draft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    } else {
                        Text(currentURL).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("内置软件源地址")
                } footer: {
                    Text("开启后该源置顶显示在软件源列表，应用自动同步。地址可在此修改。")
                }

                Section {
                    // 修改：进入/退出编辑
                    Button {
                        if editing { draft = currentURL }
                        editing.toggle()
                    } label: {
                        Label(editing ? "取消修改" : "修改", systemImage: "pencil")
                    }
                    // 保存：写入地址并重新加载
                    Button {
                        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            store.settings.builtinSourceURL = trimmed
                        }
                        editing = false
                        savedTip = true
                        store.sources.reloadBuiltin()
                        Task { await store.sources.syncBuiltin() }
                    } label: {
                        Label("保存", systemImage: "square.and.arrow.down")
                    }
                    .disabled(editing && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    // 开 / 关：标准开关
                    Toggle("启用内置软件源", isOn: Binding(
                        get: { enabled },
                        set: { on in
                            store.settings.builtinSourceEnabled = on
                            store.sources.reloadBuiltin()
                            if on { Task { await store.sources.syncBuiltin() } }
                        }
                    ))
                } header: {
                    Text("操作")
                }

                if savedTip {
                    Section { Text("已保存").foregroundStyle(.green) }
                }
            }
            .navigationTitle("内置软件源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { draft = currentURL }
        }
    }
}
