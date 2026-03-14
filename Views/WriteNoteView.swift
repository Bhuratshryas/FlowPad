import PhotosUI
import SwiftUI

struct WriteNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var bodyText = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var attachedImageFileNames: [String] = []
    @FocusState private var bodyFocused: Bool

    var onSave: (_ title: String, _ body: String, _ imageFileNames: [String]) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TextField("Title", text: $title, axis: .vertical)
                        .font(.title2.bold())
                        .submitLabel(.next)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 6)

                    TextEditor(text: $bodyText)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .focused($bodyFocused)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(minHeight: 260)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !attachedImageFileNames.isEmpty {
                        imageThumbnailsRow
                    }
                }
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.surfaceRaised)
            .preferredColorScheme(.light)
            .toolbarColorScheme(.light, for: .navigationBar)
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            insertFormat("\n## ")
                        } label: {
                            Label("Title", systemImage: "textformat.size.larger")
                        }
                        Button {
                            insertFormat("\n### ")
                        } label: {
                            Label("Heading", systemImage: "textformat")
                        }
                        Button {
                            insertFormat("\n- ")
                        } label: {
                            Label("Bullet List", systemImage: "list.bullet")
                        }
                        Divider()
                        PhotosPicker(
                            selection: $selectedPhotoItems,
                            maxSelectionCount: 10,
                            matching: .images
                        ) {
                            Label("Photo", systemImage: "photo.badge.plus")
                        }
                        .onChange(of: selectedPhotoItems) { _, newItems in
                            Task { await savePickedImages(newItems) }
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveNote()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            if bodyText.isEmpty && title.isEmpty {
                bodyFocused = true
            }
        }
    }

    private func insertFormat(_ prefix: String) {
        let trim = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if bodyText.isEmpty {
            bodyText = (trim.hasPrefix("\n") ? String(trim.dropFirst()) : trim) + " "
        } else {
            bodyText += prefix + " "
        }
    }

    private var imageThumbnailsRow: some View {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(attachedImageFileNames.enumerated()), id: \.offset) { index, name in
                    let url = docs.appendingPathComponent(name)
                    if let data = try? Data(contentsOf: url),
                       let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Button(role: .destructive) {
                                    removeImage(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.red)
                                        .shadow(radius: 2)
                                }
                                .padding(4)
                            }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(AppTheme.surfaceRaised)
    }

    private func removeImage(at index: Int) {
        let name = attachedImageFileNames[index]
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        try? FileManager.default.removeItem(at: docs.appendingPathComponent(name))
        attachedImageFileNames.remove(at: index)
    }

    private func savePickedImages(_ items: [PhotosPickerItem]) async {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  !data.isEmpty else { continue }
            let name = "img_\(UUID().uuidString).jpg"
            let url = docs.appendingPathComponent(name)
            try? data.write(to: url)
            await MainActor.run {
                attachedImageFileNames.append(name)
            }
        }
        await MainActor.run {
            selectedPhotoItems = []
        }
    }

    private func saveNote() {
        onSave(
            title.trimmingCharacters(in: .whitespacesAndNewlines),
            bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
            attachedImageFileNames
        )
        dismiss()
    }
}
