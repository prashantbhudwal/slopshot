import AppKit

enum SaveLocationSlot: Sendable {
  case primary
  case secondary
}

@MainActor
final class PromptPanelController: NSObject, NSTextViewDelegate {
  let id: UUID
  private let panel: PromptPanel
  private let textView = PromptTextView()
  private let scrollView = NSScrollView()
  private let completion: (String?, SaveLocationSlot, @escaping () -> Void) -> Void
  private let dismissalDelay: TimeInterval
  private let dragFiles: () -> [URL]
  private let onDragged: () -> Void
  private var timer: Timer?
  private var dismissalDeadline: Date?
  private var hasInteracted = false
  private var hasCompleted = false
  private var previewHeight: CGFloat = 0
  private var panelWidth: CGFloat = 0

  private let minimumInputHeight: CGFloat = 58
  private let maximumInputHeight: CGFloat = 200

  init(
    id: UUID,
    imageURLs: [URL],
    savePlaceholder: String,
    dismissalDelay: TimeInterval = 5,
    dragFiles: @escaping () -> [URL] = { [] },
    onDragged: @escaping () -> Void = {},
    completion: @escaping (String?, SaveLocationSlot, @escaping () -> Void) -> Void
  ) {
    self.id = id
    self.completion = completion
    self.dismissalDelay = dismissalDelay
    self.dragFiles = dragFiles
    self.onDragged = onDragged
    panel = PromptPanel(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    super.init()
    textView.focusedPlaceholder = savePlaceholder
    configurePanel(imageURLs: imageURLs)
  }

  func show(on screen: NSScreen, stackIndex: Int) {
    let frame = panel.frame
    let margin: CGFloat = 20
    let origin = NSPoint(
      x: screen.visibleFrame.maxX - frame.width - margin,
      y: screen.visibleFrame.minY + margin + CGFloat(stackIndex) * (frame.height + 12)
    )
    panel.setFrameOrigin(origin)
    #if DEBUG
      if (CommandLine.arguments.contains("--show-prompt")
        && !CommandLine.arguments.contains("--prompt-idle-test"))
        || CommandLine.arguments.contains("--capture-full")
      {
        panel.makeKeyAndOrderFront(nil)
      } else {
        panel.orderFrontRegardless()
      }
    #else
      panel.orderFrontRegardless()
    #endif
    startTimer()
  }

  func updateStackIndex(_ index: Int, on screen: NSScreen) {
    let margin: CGFloat = 20
    let origin = NSPoint(
      x: screen.visibleFrame.maxX - panel.frame.width - margin,
      y: screen.visibleFrame.minY + margin + CGFloat(index) * (panel.frame.height + 12)
    )
    panel.setFrameOrigin(origin)
  }

  func focusComposer() {
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(textView)
    pauseTimer()
  }

  private func configurePanel(imageURLs: [URL]) {
    panel.level = .floating
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    let surface = NSView()
    surface.translatesAutoresizingMaskIntoConstraints = false
    surface.wantsLayer = true
    surface.layer?.backgroundColor = NSColor.clear.cgColor
    panel.contentView = surface

    let preview = DraggableImageView()
    preview.translatesAutoresizingMaskIntoConstraints = false
    let previewImage = imageURLs.first
      .flatMap { try? Data(contentsOf: $0) }
      .flatMap(NSImage.init(data:))
    previewImage?.cacheMode = .always
    preview.image = previewImage
    preview.toolTip =
      imageURLs.count > 1
      ? "Drag \(imageURLs.count) screenshots"
      : "Drag screenshot"
    preview.setAccessibilityRole(.image)
    preview.setAccessibilityLabel(imageURLs.count > 1 ? "Screenshots" : "Screenshot")
    preview.fileURLsProvider = { [weak self] in
      self?.pauseTimer()
      return self?.dragFiles() ?? []
    }
    preview.onDraggingStarted = { [weak self] in self?.finishDragging() }
    preview.wantsLayer = true
    preview.layer?.backgroundColor = NSColor.clear.cgColor

    textView.delegate = self
    textView.font = .systemFont(ofSize: 14)
    textView.textColor = .labelColor
    textView.backgroundColor = .clear
    textView.drawsBackground = false
    textView.isRichText = false
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = true
    textView.autoresizingMask = [.width]
    textView.minSize = .zero
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.containerSize = NSSize(
      width: 0,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.textContainerInset = NSSize(width: 0, height: 3)
    textView.toolTip =
      "Return saves to Location 1. Command-Return saves to Location 2. Shift-Return adds a line."
    textView.onInteraction = { [weak self] in self?.pauseTimer() }
    textView.onCommit = { [weak self] slot in self?.finishWithCurrentText(slot: slot) }
    textView.onCancel = { [weak self] in self?.finish(prompt: nil, slot: .primary) }

    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.documentView = textView
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = false
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.verticalScrollElasticity = .automatic
    scrollView.borderType = .noBorder

    let inputSurface = PromptInputSurface()
    inputSurface.translatesAutoresizingMaskIntoConstraints = false
    inputSurface.wantsLayer = true
    inputSurface.layer?.cornerRadius = 10
    inputSurface.layer?.cornerCurve = .continuous
    inputSurface.layer?.shadowColor = NSColor.black.cgColor
    inputSurface.layer?.shadowOpacity = 0.18
    inputSurface.layer?.shadowRadius = 8
    inputSurface.layer?.shadowOffset = NSSize(width: 0, height: -2)

    surface.addSubview(preview)
    surface.addSubview(inputSurface)
    inputSurface.addSubview(scrollView)

    let bitmap = previewImage?.representations.compactMap { $0 as? NSBitmapImageRep }.first
    let sourceWidth = max(1, CGFloat(bitmap?.pixelsWide ?? Int(previewImage?.size.width ?? 16)))
    let sourceHeight = max(1, CGFloat(bitmap?.pixelsHigh ?? Int(previewImage?.size.height ?? 9)))
    let scale = min(380 / sourceWidth, 220 / sourceHeight)
    let displayedWidth = ceil(sourceWidth * scale)
    previewHeight = ceil(sourceHeight * scale)
    let width = max(180, displayedWidth)
    panelWidth = width
    let size = NSSize(width: width, height: previewHeight + 10 + minimumInputHeight)
    panel.setContentSize(size)
    NSLayoutConstraint.activate([
      preview.topAnchor.constraint(equalTo: surface.topAnchor),
      preview.centerXAnchor.constraint(equalTo: surface.centerXAnchor),
      preview.widthAnchor.constraint(equalToConstant: displayedWidth),
      preview.heightAnchor.constraint(equalToConstant: previewHeight),

      inputSurface.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 10),
      inputSurface.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
      inputSurface.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
      inputSurface.bottomAnchor.constraint(equalTo: surface.bottomAnchor),

      scrollView.topAnchor.constraint(equalTo: inputSurface.topAnchor, constant: 7),
      scrollView.leadingAnchor.constraint(equalTo: inputSurface.leadingAnchor, constant: 14),
      scrollView.trailingAnchor.constraint(equalTo: inputSurface.trailingAnchor, constant: -14),
      scrollView.bottomAnchor.constraint(equalTo: inputSurface.bottomAnchor, constant: -7),
    ])
    surface.layoutSubtreeIfNeeded()
    textView.setFrameSize(scrollView.contentSize)
  }

  private func startTimer() {
    timer?.invalidate()
    guard !hasInteracted else { return }
    dismissalDeadline = Date().addingTimeInterval(dismissalDelay)
    updateCountdown()
    let countdownTimer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.updateCountdown() }
    }
    RunLoop.main.add(countdownTimer, forMode: .common)
    timer = countdownTimer
  }

  private func pauseTimer() {
    hasInteracted = true
    timer?.invalidate()
    timer = nil
    dismissalDeadline = nil
    textView.unfocusedPlaceholder = textView.focusedPlaceholder
  }

  private func updateCountdown() {
    guard let dismissalDeadline else { return }
    let remaining = Int(ceil(dismissalDeadline.timeIntervalSinceNow))
    guard remaining > 0 else {
      finish(prompt: nil, slot: .primary)
      return
    }
    textView.unfocusedPlaceholder = "Auto-saves in \(remaining)s"
  }

  private func finishWithCurrentText(slot: SaveLocationSlot) {
    let prompt = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
    finish(prompt: prompt.isEmpty ? nil : prompt, slot: slot)
  }

  private func finishDragging() {
    guard !hasCompleted else { return }
    hasCompleted = true
    timer?.invalidate()
    panel.orderOut(nil)
    onDragged()
  }

  private func finish(prompt: String?, slot: SaveLocationSlot) {
    guard !hasCompleted else { return }
    hasCompleted = true
    timer?.invalidate()
    textView.isEditable = false
    completion(prompt, slot) { [weak self] in
      self?.panel.orderOut(nil)
    }
  }

  func textDidChange(_ notification: Notification) {
    pauseTimer()
    resizeEditorToFit()
  }

  func textViewDidChangeSelection(_ notification: Notification) {
    pauseTimer()
  }

  private func resizeEditorToFit() {
    guard let layoutManager = textView.layoutManager,
      let textContainer = textView.textContainer
    else { return }

    let viewportWidth = max(1, scrollView.contentSize.width)
    if textView.frame.width != viewportWidth {
      textView.setFrameSize(
        NSSize(width: viewportWidth, height: max(1, textView.frame.height))
      )
    }
    layoutManager.ensureLayout(for: textContainer)

    let textHeight = ceil(
      layoutManager.usedRect(for: textContainer).height
        + textView.textContainerInset.height * 2
    )
    let desiredInputHeight = min(
      maximumInputHeight,
      max(minimumInputHeight, textHeight + 14)
    )
    let desiredPanelHeight = previewHeight + 10 + desiredInputHeight
    let currentFrame = panel.frame

    if abs(currentFrame.height - desiredPanelHeight) >= 1 {
      panel.setFrame(
        NSRect(
          x: currentFrame.minX,
          y: currentFrame.minY,
          width: panelWidth,
          height: desiredPanelHeight
        ),
        display: true
      )
      panel.contentView?.layoutSubtreeIfNeeded()
    }

    let contentHeight = max(scrollView.contentSize.height, textHeight)
    textView.setFrameSize(
      NSSize(width: max(1, scrollView.contentSize.width), height: contentHeight)
    )
    scrollView.hasVerticalScroller = textHeight + 14 > maximumInputHeight
    textView.scrollRangeToVisible(textView.selectedRange())
  }
}

private final class DraggableImageView: NSView, NSDraggingSource {
  var image: NSImage? { didSet { needsDisplay = true } }
  var fileURLsProvider: (() -> [URL])?
  var onDraggingStarted: (() -> Void)?
  private var isDraggingFiles = false

  override var isOpaque: Bool { false }
  override var acceptsFirstResponder: Bool { false }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    image?.draw(
      in: bounds,
      from: .zero,
      operation: .sourceOver,
      fraction: 1,
      respectFlipped: true,
      hints: [.interpolation: NSImageInterpolation.high]
    )
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(nil)
    isDraggingFiles = false
  }

  override func mouseDragged(with event: NSEvent) {
    guard !isDraggingFiles else { return }
    let urls = fileURLsProvider?() ?? []
    guard !urls.isEmpty else { return }
    isDraggingFiles = true

    let items = urls.map { url -> NSDraggingItem in
      let item = NSDraggingItem(pasteboardWriter: url as NSURL)
      item.setDraggingFrame(bounds, contents: image)
      return item
    }
    beginDraggingSession(with: items, event: event, source: self)
    onDraggingStarted?()
  }

  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    .copy
  }

  func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}

private final class PromptPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

private final class PromptTextView: NSTextView {
  var onInteraction: (() -> Void)?
  var onCommit: ((SaveLocationSlot) -> Void)?
  var onCancel: (() -> Void)?

  var focusedPlaceholder = "↩ Save"
  var unfocusedPlaceholder = "Auto-saves in 5s" {
    didSet { needsDisplay = true }
  }

  override func becomeFirstResponder() -> Bool {
    let result = super.becomeFirstResponder()
    if result {
      // On the first click, AppKit assigns the responder before marking the panel key.
      // Do not gate this interaction on window.isKeyWindow.
      onInteraction?()
      needsDisplay = true
    }
    return result
  }

  override func resignFirstResponder() -> Bool {
    let result = super.resignFirstResponder()
    if result { needsDisplay = true }
    return result
  }

  override func mouseDown(with event: NSEvent) {
    onInteraction?()
    super.mouseDown(with: event)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    textColor = .labelColor
    needsDisplay = true
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard modifiers.contains(.command),
      let key = event.charactersIgnoringModifiers?.lowercased()
    else {
      return super.performKeyEquivalent(with: event)
    }

    switch key {
    case "a":
      selectAll(nil)
    case "c":
      copy(nil)
    case "v":
      paste(nil)
      onInteraction?()
    case "x":
      cut(nil)
      onInteraction?()
    case "z":
      if modifiers.contains(.shift) {
        undoManager?.redo()
      } else {
        undoManager?.undo()
      }
      onInteraction?()
    default:
      return super.performKeyEquivalent(with: event)
    }
    return true
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {
      onCancel?()
      return
    }
    if event.keyCode == 36 || event.keyCode == 76 {
      if event.modifierFlags.contains(.shift) {
        insertNewline(nil)
      } else {
        let slot: SaveLocationSlot =
          event.modifierFlags.contains(.command) ? .secondary : .primary
        onCommit?(slot)
      }
      return
    }
    onInteraction?()
    super.keyDown(with: event)
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard string.isEmpty else { return }
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font ?? NSFont.systemFont(ofSize: 14),
      .foregroundColor: NSColor.placeholderTextColor,
    ]
    let isActivelyFocused = window?.isKeyWindow == true && window?.firstResponder === self
    let placeholder = isActivelyFocused ? focusedPlaceholder : unfocusedPlaceholder
    placeholder.draw(at: NSPoint(x: 5, y: 4), withAttributes: attributes)
  }
}

private final class PromptInputSurface: NSView {
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateBackgroundColor()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateBackgroundColor()
  }

  private func updateBackgroundColor() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
  }
}
