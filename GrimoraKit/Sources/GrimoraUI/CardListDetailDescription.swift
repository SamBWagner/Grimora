import GrimoraCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

extension CardListDetailView {
    var descriptionRTFDDataBinding: Binding<Data?> {
        Binding {
            descriptionRTFDData
        } set: { newValue in
            guard descriptionRTFDData != newValue else {
                return
            }
            descriptionRTFDData = newValue
            descriptionDidChange()
        }
    }

    var descriptionPlainTextBinding: Binding<String> {
        Binding {
            descriptionPlainText
        } set: { newValue in
            guard descriptionPlainText != newValue else {
                return
            }
            descriptionPlainText = newValue
            descriptionDidChange()
        }
    }

    func toggleDescription(for list: CardListRecord) {
        if descriptionListID != list.id {
            syncDescriptionDraft(for: list)
        }
        isShowingDescription.toggle()
        if !isShowingDescription {
            flushDescriptionSave(forListID: list.id)
        }
    }

    func syncDescriptionDraftIfNeeded() {
        guard descriptionListID != model.selectedListID else {
            return
        }
        syncDescriptionDraft(for: model.selectedList)
    }

    func syncDescriptionDraft(for list: CardListRecord?) {
        descriptionSaveTask?.cancel()
        descriptionListID = list?.id
        descriptionRTFDData = list?.descriptionRTFDData
        descriptionPlainText = list?.descriptionPlainText ?? ""
        descriptionIsDirty = false
    }

    func descriptionDidChange() {
        guard descriptionListID != nil else {
            return
        }
        descriptionIsDirty = true
        scheduleDescriptionSave()
    }

    func scheduleDescriptionSave() {
        guard let listID = descriptionListID else {
            return
        }

        let rtfdData = descriptionRTFDData
        let plainText = descriptionPlainText
        descriptionSaveTask?.cancel()
        descriptionSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else {
                return
            }
            model.saveCardListDescription(forListID: listID, rtfdData: rtfdData, plainText: plainText)
            if descriptionListID == listID,
               descriptionRTFDData == rtfdData,
               descriptionPlainText == plainText
            {
                descriptionIsDirty = false
            }
        }
    }

    func flushDescriptionSave(forListID listID: CardListRecord.ID?) {
        descriptionSaveTask?.cancel()
        guard descriptionIsDirty, let listID else {
            return
        }
        model.saveCardListDescription(forListID: listID, rtfdData: descriptionRTFDData, plainText: descriptionPlainText)
        descriptionIsDirty = false
    }
}
