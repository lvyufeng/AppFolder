import AppFolderKit
import Contacts
import ContactsUI
import SwiftUI

extension ContactTarget.Operation {
    var appLocalizedName: String {
        switch self {
        case .phone: String(localized: "电话")
        case .message: String(localized: "短信")
        case .faceTimeAudio: String(localized: "FaceTime 语音")
        case .faceTimeVideo: String(localized: "FaceTime 视频")
        }
    }
}

/// Selection and editing produce only a local snapshot. This screen never
/// constructs or opens a communication URL or reads a contact store.
struct ContactEditorView: View {
    let item: GroupItem?
    let onSave: (String, ContactTarget) -> Bool
    @State private var name: String
    @State private var number: String
    @State private var operation: ContactTarget.Operation
    @State private var showsContactPicker = false
    @State private var pickerRequestID: UUID?
    @State private var isSubmitting = false
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    init(item: GroupItem?, onSave: @escaping (String, ContactTarget) -> Bool) {
        self.item = item
        self.onSave = onSave
        _name = State(initialValue: item?.name ?? "")
        _number = State(initialValue: item?.contactTarget?.number ?? "")
        _operation = State(initialValue: item?.contactTarget?.operation ?? .phone)
    }

    private var target: ContactTarget? { ContactTarget(operation: operation, number: number) }
    private var title: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? target?.number ?? "" : trimmed
    }
    private var validName: Bool {
        title.count <= SavedGroup.maximumNameLength && title.utf8.count <= 512
            && !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    private var canSave: Bool {
        !isSubmitting && !showsContactPicker && target != nil && !title.isEmpty && validName
    }

    var body: some View {
        let presentedPickerID = pickerRequestID
        NavigationStack {
            Form {
                Section {
                    Button {
                        guard !showsContactPicker, !isSubmitting else { return }
                        pickerRequestID = UUID()
                        showsContactPicker = true
                    } label: { Label("从联系人选择号码", systemImage: "person.crop.circle.badge.plus") }
                        .accessibilityIdentifier("contactEditor.chooseNumber")
                    TextField("显示名称（可选）", text: $name)
                        .accessibilityIdentifier("contactEditor.name")
                    TextField("电话号码", text: $number)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("contactEditor.number")
                } footer: {
                    Text("只接收你选中的姓名和一个电话号码，不读取联系人照片。也可直接输入；未填写名称时显示号码。")
                }

                Section {
                    Picker("联系操作", selection: $operation) {
                        ForEach(ContactTarget.Operation.allCases, id: \.self) { value in
                            Label(value.appLocalizedName, systemImage: value.systemImage).tag(value)
                        }
                    }
                    .accessibilityIdentifier("contactEditor.operation")
                    if let target {
                        HStack(spacing: 12) {
                            ContactArtwork(target: target, cornerRadius: 10, maxPixelSize: 64)
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: operation.appLocalizedName)
                                Text(target.number).textSelection(.enabled).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("contactEditor.destination")
                    } else if !number.isEmpty {
                        Text("请输入一个有效电话号码，可包含国家或地区代码；不支持分机、多号码或链接。")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("contactEditor.numberError")
                    }
                } header: {
                    Text("将使用的号码与操作")
                } footer: {
                    Text("点击图块后先进入 AppFolder。电话和短信交由系统处理；FaceTime 需要再点开始。选择、预览和保存都不会发起联系。")
                }

                if !validName {
                    Section {
                        Text("名称未保存。请缩短名称（最多 80 个字符），并移除换行或不支持的字符。")
                            .foregroundStyle(.red)
                    }
                }
                if failed {
                    Section {
                        Text("联系人未应用到分组。请检查分组是否已满，然后重试。")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("contactEditor.saveError")
                    }
                }
                Section {
                    Text("姓名和号码按当前选择保存，不会随通讯录自动更新。号码变更后，请重新选择或手动修改。")
                    Text("联系人图块无需配置系统动作。这里的修改在保存分组后应用。")
                }
                .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle(item == nil ? LocalizedStringKey("添加联系人") : LocalizedStringKey("编辑联系人"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { pickerRequestID = nil; dismiss() }
                        .accessibilityIdentifier("contactEditor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(item == nil ? LocalizedStringKey("添加") : LocalizedStringKey("应用修改"), action: save)
                        .disabled(!canSave)
                        .accessibilityIdentifier("contactEditor.save")
                }
            }
            .onChange(of: name) { _, _ in failed = false }
            .onChange(of: number) { _, _ in failed = false }
            .onChange(of: operation) { _, _ in failed = false }
            .sheet(isPresented: $showsContactPicker, onDismiss: {
                if !showsContactPicker { pickerRequestID = nil }
            }) {
                ContactPhonePicker { selection in
                    guard let presentedPickerID, pickerRequestID == presentedPickerID, !isSubmitting else { return }
                    pickerRequestID = nil
                    showsContactPicker = false
                    if let selection {
                        name = selection.name
                        number = selection.number
                    }
                }
            }
        }
    }

    private func save() {
        guard !isSubmitting else { return }
        guard canSave, let target else { failed = true; return }
        isSubmitting = true
        guard onSave(title, target) else { isSubmitting = false; failed = true; return }
        pickerRequestID = nil
        dismiss()
    }
}

private struct ContactPhoneSelection {
    let name: String
    let number: String
}

/// The system owns browsing. Only strings from the final single selection leave
/// this controller; no identifier, photo, contact object or authorization is saved.
private struct ContactPhonePicker: UIViewControllerRepresentable {
    let onFinish: (ContactPhoneSelection?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        picker.predicateForSelectionOfContact = NSPredicate(format: "phoneNumbers.@count == 1")
        // False performs a property's default action, which could start a call.
        // Always return the selection and validate its type in the delegate.
        picker.predicateForSelectionOfProperty = NSPredicate(value: true)
        return picker
    }

    func updateUIViewController(_ picker: CNContactPickerViewController, context: Context) {
        context.coordinator.onFinish = onFinish
    }

    static func dismantleUIViewController(_ picker: CNContactPickerViewController, coordinator: Coordinator) {
        picker.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, @MainActor CNContactPickerDelegate {
        var onFinish: (ContactPhoneSelection?) -> Void
        private var completed = false

        init(onFinish: @escaping (ContactPhoneSelection?) -> Void) { self.onFinish = onFinish }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) { finish(nil) }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            guard contact.isKeyAvailable(CNContactPhoneNumbersKey), contact.phoneNumbers.count == 1 else {
                finish(nil)
                return
            }
            finish(selection(contact: contact, number: contact.phoneNumbers[0].value.stringValue))
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect property: CNContactProperty) {
            guard property.key == CNContactPhoneNumbersKey, let phone = property.value as? CNPhoneNumber else {
                finish(nil)
                return
            }
            finish(selection(contact: property.contact, number: phone.stringValue))
        }

        private func selection(contact: CNContact, number: String) -> ContactPhoneSelection {
            let nameKeys = CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
            let name = contact.areKeysAvailable([nameKeys])
                ? CNContactFormatter.string(from: contact, style: .fullName) ?? "" : ""
            return ContactPhoneSelection(name: name, number: number)
        }

        private func finish(_ selection: ContactPhoneSelection?) {
            guard !completed else { return }
            completed = true
            onFinish(selection)
        }
    }
}
