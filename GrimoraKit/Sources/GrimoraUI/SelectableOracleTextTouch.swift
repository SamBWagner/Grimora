#if os(iOS) || os(visionOS)
import GrimoraCore
import SwiftUI
import UIKit

@MainActor
final class OracleSelectionTextView: UITextView {
    var onIncludeSelection: ((String) -> Void)?
    var onExcludeSelection: ((String) -> Void)?

    override func editMenu(
        for textRange: UITextRange,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        let location = offset(from: beginningOfDocument, to: textRange.start)
        let length = offset(from: textRange.start, to: textRange.end)
        let range = NSRange(location: location, length: length)
        guard range.length > 0,
              range.location != NSNotFound,
              NSMaxRange(range) <= (text as NSString).length
        else {
            return UIMenu(children: suggestedActions)
        }

        let selectedText = SearchRefinement.normalizedSelectedText(
            (text as NSString).substring(with: range)
        )
        guard !selectedText.isEmpty else {
            return UIMenu(children: suggestedActions)
        }

        return UIMenu(
            children: suggestedActions + [
                UIMenu(
                    options: .displayInline,
                    children: [
                        UIAction(
                            title: "More cards with “\(selectedText)”",
                            image: UIImage(systemName: "magnifyingglass")
                        ) { [weak self] _ in
                            self?.onIncludeSelection?(selectedText)
                        },
                        UIAction(
                            title: "Exclude “\(selectedText)”",
                            image: UIImage(systemName: "line.3.horizontal.decrease.circle")
                        ) { [weak self] _ in
                            self?.onExcludeSelection?(selectedText)
                        },
                    ]
                ),
            ]
        )
    }
}

struct SelectableOracleText: UIViewRepresentable {
    var text: String
    var color: GrimoraColorValue
    var onIncludeSelection: (String) -> Void
    var onExcludeSelection: (String) -> Void

    func makeUIView(context: Context) -> OracleSelectionTextView {
        let textView = OracleSelectionTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.font = .grimoraBody
        textView.accessibilityIdentifier = "card-detail-oracle-text"
        update(textView)
        return textView
    }

    func updateUIView(_ textView: OracleSelectionTextView, context: Context) {
        update(textView)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView textView: OracleSelectionTextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width else {
            return nil
        }
        let size = textView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: ceil(size.height))
    }

    private func update(_ textView: OracleSelectionTextView) {
        if textView.text != text {
            textView.text = text
        }
        textView.textColor = UIColor(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.opacity
        )
        textView.onIncludeSelection = onIncludeSelection
        textView.onExcludeSelection = onExcludeSelection
    }
}
#endif
