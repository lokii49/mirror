import UIKit

final class NotesToolbar: UIInputView {
    private let coordinator: RichTextCoordinator

    // Format buttons we need to keep refs to for active-state updates
    private weak var boldBtn: UIButton?
    private weak var italicBtn: UIButton?
    private weak var underlineBtn: UIButton?
    private weak var strikeBtn: UIButton?
    private weak var highlightBtn: UIButton?

    init(coordinator: RichTextCoordinator) {
        self.coordinator = coordinator
        super.init(
            frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 54),
            inputViewStyle: .keyboard
        )
        autoresizingMask = [.flexibleWidth]
        backgroundColor = .clear
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Active-state updates

    func update(_ state: FormatState) {
        toggleActive(boldBtn,      on: state.isBold)
        toggleActive(italicBtn,    on: state.isItalic)
        toggleActive(underlineBtn, on: state.isUnderline)
        toggleActive(strikeBtn,    on: state.isStrikethrough)
        toggleActive(highlightBtn, on: state.isHighlighted)
    }

    private func toggleActive(_ button: UIButton?, on: Bool) {
        guard let button else { return }
        var c = button.configuration ?? .plain()
        c.background.backgroundColor = on
            ? UIColor.label.withAlphaComponent(0.12)
            : .clear
        button.configuration = c
    }

    // MARK: - Build

    private func build() {
        // Shadow host — must NOT clip so shadow bleeds outside
        let shadow = UIView()
        shadow.translatesAutoresizingMaskIntoConstraints = false
        shadow.layer.shadowColor = UIColor.black.cgColor
        shadow.layer.shadowOpacity = 0.10
        shadow.layer.shadowRadius = 14
        shadow.layer.shadowOffset = CGSize(width: 0, height: 4)
        shadow.layer.cornerRadius = 22
        shadow.layer.cornerCurve = .continuous
        addSubview(shadow)

        // Frosted-glass pill
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.layer.cornerRadius = 22
        blur.layer.cornerCurve = .continuous
        blur.clipsToBounds = true
        shadow.addSubview(blur)

        // Scroll view inside the pill
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.bounces = false
        blur.contentView.addSubview(scroll)

        // All icons in one horizontal stack
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        // ── Group 1: Text style ──────────────────────────
        stack.addArrangedSubview(makeStyleBtn())
        stack.addArrangedSubview(iconBtn("checklist",          #selector(RichTextCoordinator.tbChecklist)))
        stack.addArrangedSubview(iconBtn("tablecells",         #selector(RichTextCoordinator.tbInsertTable)))
        stack.addArrangedSubview(menuBtn("paperclip",          buildAttachmentMenu()))
        stack.addArrangedSubview(iconBtn("pencil.tip.crop.circle", #selector(RichTextCoordinator.presentDrawingCanvas)))

        stack.addArrangedSubview(separator())

        // ── Group 2: Inline formatting ───────────────────
        let b = styledTextBtn(text: "B",   nsAttrs: [.font: UIFont.boldSystemFont(ofSize: 18)],   action: #selector(RichTextCoordinator.tbBold))
        let i = styledTextBtn(text: "I",   nsAttrs: [.font: UIFont.italicSystemFont(ofSize: 18)], action: #selector(RichTextCoordinator.tbItalic))
        let u = styledTextBtn(text: "U",   nsAttrs: [.font: UIFont.systemFont(ofSize: 18), .underlineStyle: NSUnderlineStyle.single.rawValue], action: #selector(RichTextCoordinator.tbUnderline))
        let s = styledTextBtn(text: "S",   nsAttrs: [.font: UIFont.systemFont(ofSize: 18), .strikethroughStyle: NSUnderlineStyle.single.rawValue], action: #selector(RichTextCoordinator.tbStrikethrough))
        let h = iconBtn("highlighter",     #selector(RichTextCoordinator.tbHighlight))
        boldBtn = b; italicBtn = i; underlineBtn = u; strikeBtn = s; highlightBtn = h
        [b, i, u, s, h].forEach { stack.addArrangedSubview($0) }
        stack.addArrangedSubview(iconBtn("link",               #selector(RichTextCoordinator.tbLink)))
        stack.addArrangedSubview(menuBtn("text.alignleft",     buildAlignmentMenu()))

        stack.addArrangedSubview(separator())

        // ── Group 3: Paragraph / indent ──────────────────
        stack.addArrangedSubview(iconBtn("decrease.indent",    #selector(RichTextCoordinator.tbOutdent)))
        stack.addArrangedSubview(iconBtn("increase.indent",    #selector(RichTextCoordinator.tbIndent)))
        stack.addArrangedSubview(iconBtn("arrow.up.to.line",   #selector(RichTextCoordinator.tbMoveUp)))
        stack.addArrangedSubview(iconBtn("arrow.down.to.line", #selector(RichTextCoordinator.tbMoveDown)))
        stack.addArrangedSubview(iconBtn("minus",              #selector(RichTextCoordinator.tbHorizontalRule)))
        stack.addArrangedSubview(menuBtn("list.bullet",        buildListMenu()))

        stack.addArrangedSubview(separator())

        // ── Keyboard dismiss ─────────────────────────────
        stack.addArrangedSubview(iconBtn("keyboard.chevron.compact.down", #selector(RichTextCoordinator.tbDismiss)))

        // MARK: Constraints
        NSLayoutConstraint.activate([
            shadow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            shadow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            shadow.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -1),
            shadow.heightAnchor.constraint(equalToConstant: 44),

            blur.leadingAnchor.constraint(equalTo: shadow.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: shadow.trailingAnchor),
            blur.topAnchor.constraint(equalTo: shadow.topAnchor),
            blur.bottomAnchor.constraint(equalTo: shadow.bottomAnchor),

            scroll.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: blur.contentView.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
    }

    // MARK: - Button factories

    /// Standard SF Symbol icon button
    private func iconBtn(_ symbol: String, _ action: Selector) -> UIButton {
        var c = UIButton.Configuration.plain()
        c.image = UIImage(systemName: symbol,
                          withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .regular))
        c.baseForegroundColor = .label
        c.contentInsets = .zero
        return makeButton(c, target: coordinator, action: action)
    }

    /// Icon button that shows a menu (no action target)
    private func menuBtn(_ symbol: String, _ menu: UIMenu) -> UIButton {
        var c = UIButton.Configuration.plain()
        c.image = UIImage(systemName: symbol,
                          withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .regular))
        c.baseForegroundColor = .label
        c.contentInsets = .zero
        let btn = makeButton(c, target: nil, action: nil)
        btn.showsMenuAsPrimaryAction = true
        btn.menu = menu
        return btn
    }

    /// "Aa" style-picker button
    private func makeStyleBtn() -> UIButton {
        var c = UIButton.Configuration.plain()
        var title = AttributedString("Aa")
        title.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        c.attributedTitle = title
        c.baseForegroundColor = .label
        c.contentInsets = .zero
        let btn = makeButton(c, target: nil, action: nil)
        btn.showsMenuAsPrimaryAction = true
        btn.menu = buildStyleMenu()
        return btn
    }

    /// Inline text-styled button for B / I / U / S
    private func styledTextBtn(text: String, nsAttrs: [NSAttributedString.Key: Any], action: Selector) -> UIButton {
        var attrs = nsAttrs
        attrs[.foregroundColor] = UIColor.label
        let nsStr = NSAttributedString(string: text, attributes: attrs)
        var c = UIButton.Configuration.plain()
        c.attributedTitle = AttributedString(nsStr)
        c.contentInsets = .zero
        return makeButton(c, target: coordinator, action: action)
    }

    /// Common button builder: sets size, highlight handler
    private func makeButton(_ config: UIButton.Configuration, target: Any?, action: Selector?) -> UIButton {
        let btn = UIButton(configuration: config)
        if let action { btn.addTarget(target, action: action, for: .touchUpInside) }
        btn.configurationUpdateHandler = { ctrl in
            guard var c = ctrl.configuration else { return }
            if ctrl.isHighlighted {
                c.background.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.6)
            } else if c.background.backgroundColor == UIColor.systemGray4.withAlphaComponent(0.6) {
                c.background.backgroundColor = .clear
            }
            ctrl.configuration = c
        }
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.widthAnchor.constraint(equalToConstant: 48).isActive = true
        return btn
    }

    /// Thin vertical divider between groups
    private func separator() -> UIView {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.separator.withAlphaComponent(0.5)
        v.widthAnchor.constraint(equalToConstant: 0.5).isActive = true
        v.heightAnchor.constraint(equalToConstant: 22).isActive = true
        // Wrap in a fixed-width container for proper spacing
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(equalToConstant: 14).isActive = true
        container.addSubview(v)
        v.centerXAnchor.constraint(equalTo: container.centerXAnchor).isActive = true
        v.centerYAnchor.constraint(equalTo: container.centerYAnchor).isActive = true
        return container
    }

    // MARK: - Menus

    private func buildAttachmentMenu() -> UIMenu {
        let cfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        func img(_ n: String) -> UIImage? { UIImage(systemName: n, withConfiguration: cfg) }
        return UIMenu(title: "", children: [
            UIAction(title: "Take Photo or Video",   image: img("camera"))             { [weak self] _ in self?.coordinator.presentCameraCapture() },
            UIAction(title: "Choose Photo or Video", image: img("photo.on.rectangle")) { [weak self] _ in self?.coordinator.presentPhotoVideoPicker() },
            UIAction(title: "Scan Documents",        image: img("doc.viewfinder"))      { [weak self] _ in self?.coordinator.presentDocumentScanner() },
            UIAction(title: "Attach File",           image: img("folder"))              { [weak self] _ in self?.coordinator.presentFilePicker() },
        ])
    }

    private func buildAlignmentMenu() -> UIMenu {
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        func img(_ n: String) -> UIImage? { UIImage(systemName: n, withConfiguration: cfg) }
        return UIMenu(title: "Alignment", children: [
            UIAction(title: "Left",    image: img("text.alignleft"))   { [weak self] _ in self?.coordinator.tbAlignLeft() },
            UIAction(title: "Center",  image: img("text.aligncenter")) { [weak self] _ in self?.coordinator.tbAlignCenter() },
            UIAction(title: "Right",   image: img("text.alignright"))  { [weak self] _ in self?.coordinator.tbAlignRight() },
            UIAction(title: "Justify", image: img("text.justify"))     { [weak self] _ in self?.coordinator.setAlignment(.justified) },
        ])
    }

    private func buildListMenu() -> UIMenu {
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        func img(_ n: String) -> UIImage? { UIImage(systemName: n, withConfiguration: cfg) }
        return UIMenu(title: "List", children: [
            UIAction(title: "Checklist",     image: img("checklist"))    { [weak self] _ in self?.coordinator.tbChecklist() },
            UIAction(title: "Bulleted List", image: img("list.bullet"))  { [weak self] _ in self?.coordinator.tbBullet() },
            UIAction(title: "Numbered List", image: img("list.number"))  { [weak self] _ in self?.coordinator.tbNumbered() },
        ])
    }

    private func buildStyleMenu() -> UIMenu {
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        func img(_ n: String) -> UIImage? { UIImage(systemName: n, withConfiguration: cfg) }
        return UIMenu(title: "", children: [
            UIMenu(title: "Text Style", options: .displayInline, children: [
                UIAction(title: "Title",      image: img("textformat.size.larger"))                  { [weak self] _ in self?.coordinator.setTextStyle(.title) },
                UIAction(title: "Heading",    image: img("textformat"))                              { [weak self] _ in self?.coordinator.setTextStyle(.heading) },
                UIAction(title: "Subheading", image: img("textformat.size.smaller"))                 { [weak self] _ in self?.coordinator.setTextStyle(.subheading) },
                UIAction(title: "Body",       image: img("text.alignleft"))                          { [weak self] _ in self?.coordinator.setTextStyle(.body) },
                UIAction(title: "Monospaced", image: img("chevron.left.forwardslash.chevron.right")) { [weak self] _ in self?.coordinator.setTextStyle(.monospaced) },
            ]),
            UIMenu(title: "Format", options: .displayInline, children: [
                UIAction(title: "Bold",          image: img("bold"))          { [weak self] _ in self?.coordinator.tbBold() },
                UIAction(title: "Italic",        image: img("italic"))        { [weak self] _ in self?.coordinator.tbItalic() },
                UIAction(title: "Underline",     image: img("underline"))     { [weak self] _ in self?.coordinator.tbUnderline() },
                UIAction(title: "Strikethrough", image: img("strikethrough")) { [weak self] _ in self?.coordinator.tbStrikethrough() },
                UIAction(title: "Highlight",     image: img("highlighter"))   { [weak self] _ in self?.coordinator.tbHighlight() },
            ]),
        ])
    }
}
