#if os(macOS)
    import AppKit
    import Carbon.HIToolbox

    public extension KeyboardShortcuts {
        enum PostOnChange {
            case reset
        }

        /**
         A `NSView` that lets the user record a keyboard shortcut.

         You would usually put this in your settings window.

         It automatically prevents choosing a keyboard shortcut that is already taken by the system or by the app's main menu by showing a user-friendly alert to the user.

         It takes care of storing the keyboard shortcut in `UserDefaults` for you.

         ```swift
         import AppKit
         import KeyboardShortcuts

         final class SettingsViewController: NSViewController {
         	override func loadView() {
         		view = NSView()

         		let recorder = KeyboardShortcuts.RecorderCocoa(for: .toggleUnicornMode)
         		view.addSubview(recorder)
         	}
         }
         ```
         */
        final class RecorderCocoa: NSSearchField, NSSearchFieldDelegate {
            private let minimumWidth = 130.0
            private let onChange: ((_ shortcut: Shortcut?) -> PostOnChange)?
            private var access: KeyboardShortcuts.Access = .systemGlobal
            private var canBecomeKey = false
            private var eventMonitor: LocalEventMonitor?
            private var shortcutsNameChangeObserver: NSObjectProtocol?
            private var windowDidResignKeyObserver: NSObjectProtocol?
            private var windowDidBecomeKeyObserver: NSObjectProtocol?

            /**
             The shortcut name for the recorder.

             Can be dynamically changed at any time.
             */
            public var shortcutName: Name {
                didSet {
                    guard shortcutName != oldValue else {
                        return
                    }

                    setStringValue(name: shortcutName)

                    // This doesn't seem to be needed anymore, but I cannot test on older OS versions, so keeping it just in case.
                    if #unavailable(macOS 12) {
                        DispatchQueue.main.async { [self] in
                            // Prevents the placeholder from being cut off.
                            blur()
                        }
                    }
                }
            }

            /// :nodoc:
            override public var canBecomeKeyView: Bool { canBecomeKey }

            /// :nodoc:
            override public var intrinsicContentSize: CGSize {
                var size = super.intrinsicContentSize
                size.width = minimumWidth
                return size
            }

            private var cancelButton: NSButtonCell?

            private var showsCancelButton: Bool {
                get { (cell as? NSSearchFieldCell)?.cancelButtonCell != nil }
                set {
                    (cell as? NSSearchFieldCell)?.cancelButtonCell = newValue ? cancelButton : nil
                }
            }

            /**
             - Parameter name: Strongly-typed keyboard shortcut name.
             - Parameter onChange: Callback which will be called when the keyboard shortcut is changed/removed by the user. This can be useful when you need more control. For example, when migrating from a different keyboard shortcut solution and you need to store the keyboard shortcut somewhere yourself instead of relying on the built-in storage. However, it's strongly recommended to just rely on the built-in storage when possible.
             */
            public required init(
                for name: Name,
                access: KeyboardShortcuts.Access = .systemGlobal,
                onChange: ((_ shortcut: Shortcut?) -> PostOnChange)? = nil
            ) {
                shortcutName = name
                self.onChange = onChange
                self.access = access

                super.init(frame: .zero)
                delegate = self
                placeholderString = "record_shortcut".localized
                alignment = .center
                (cell as? NSSearchFieldCell)?.searchButtonCell = nil

                wantsLayer = true
                setContentHuggingPriority(.defaultHigh, for: .vertical)
                setContentHuggingPriority(.defaultHigh, for: .horizontal)

                // Hide the cancel button when not showing the shortcut so the placeholder text is properly centered. Must be last.
                cancelButton = (cell as? NSSearchFieldCell)?.cancelButtonCell

                setStringValue(name: name)

                setUpEvents()
            }

            @available(*, unavailable)
            public required init?(coder _: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            private func setStringValue(name _: KeyboardShortcuts.Name) {
                stringValue = getShortcut(for: shortcutName).map { "\($0)" } ?? ""

                // If `stringValue` is empty, hide the cancel button to let the placeholder center.
                showsCancelButton = !stringValue.isEmpty
            }

            private func setUpEvents() {
                shortcutsNameChangeObserver = NotificationCenter.default.addObserver(forName: .shortcutByNameDidChange, object: nil, queue: nil) { [weak self] notification in
                    guard
                        let self,
                        let nameInNotification = notification.userInfo?["name"] as? KeyboardShortcuts.Name,
                        nameInNotification == self.shortcutName
                    else {
                        return
                    }

                    self.setStringValue(name: nameInNotification)
                }
            }

            private func endRecording() {
                eventMonitor = nil
                placeholderString = "record_shortcut".localized
                showsCancelButton = !stringValue.isEmpty
                restoreCaret()
                KeyboardShortcuts.isPaused = false
            }

            private func preventBecomingKey() {
                canBecomeKey = false

                // Prevent the control from receiving the initial focus.
                DispatchQueue.main.async { [self] in
                    canBecomeKey = true
                }
            }

            /// :nodoc:
            public func controlTextDidChange(_: Notification) {
                if stringValue.isEmpty {
                    saveShortcut(nil)
                }

                showsCancelButton = !stringValue.isEmpty

                if stringValue.isEmpty {
                    // Hack to ensure that the placeholder centers after the above `showsCancelButton` setter.
                    focus()
                }
            }

            /// :nodoc:
            public func controlTextDidEndEditing(_: Notification) {
                endRecording()
            }

            /// :nodoc:
            override public func viewDidMoveToWindow() {
                guard let window else {
                    windowDidResignKeyObserver = nil
                    windowDidBecomeKeyObserver = nil
                    endRecording()
                    return
                }

                // Ensures the recorder stops when the window is hidden.
                // This is especially important for Settings windows, which as of macOS 13.5, only hides instead of closes when you click the close button.
                windowDidResignKeyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: nil) { [weak self] _ in
                    guard
                        let self,
                        let window = self.window
                    else {
                        return
                    }

                    self.endRecording()
                    window.makeFirstResponder(nil)
                }

                // Ensures the recorder does not receive initial focus when a hidden window becomes unhidden.
                windowDidBecomeKeyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: nil) { [weak self] _ in
                    self?.preventBecomingKey()
                }

                preventBecomingKey()
            }

            /// :nodoc:
            override public func becomeFirstResponder() -> Bool {
                let shouldBecomeFirstResponder = super.becomeFirstResponder()

                guard shouldBecomeFirstResponder else {
                    return shouldBecomeFirstResponder
                }

                placeholderString = "press_shortcut".localized
                showsCancelButton = !stringValue.isEmpty
                hideCaret()
                KeyboardShortcuts.isPaused = true // The position here matters.

                eventMonitor = LocalEventMonitor(events: [.keyDown, .leftMouseUp, .rightMouseUp]) { [weak self] event in
                    guard let self else {
                        return nil
                    }

                    let clickPoint = self.convert(event.locationInWindow, from: nil)
                    let clickMargin = 3.0

                    if
                        event.type == .leftMouseUp || event.type == .rightMouseUp,
                        !self.bounds.insetBy(dx: -clickMargin, dy: -clickMargin).contains(clickPoint)
                    {
                        self.blur()
                        return event
                    }

                    guard event.isKeyEvent else {
                        return nil
                    }

                    if
                        event.modifiers.isEmpty,
                        event.specialKey == .tab
                    {
                        self.blur()

                        // We intentionally bubble up the event so it can focus the next responder.
                        return event
                    }

                    if
                        event.modifiers.isEmpty,
                        event.keyCode == kVK_Escape // TODO: Make this strongly typed.
                    {
                        self.blur()
                        return nil
                    }

                    if
                        event.modifiers.isEmpty,
                        event.specialKey == .delete
                        || event.specialKey == .deleteForward
                        || event.specialKey == .backspace
                    {
                        self.clear()
                        return nil
                    }

                    // The “shift” key is not allowed without other modifiers or a function key, since it doesn't actually work.
                    guard
                        var shortcut = Shortcut(event: event)
                    else {
                        NSSound.beep()
                        return nil
                    }

                    shortcut.access = self.access
                    if event.modifiers.subtracting(.shift).isEmpty && event.specialKey?.isFunctionKey != true {
                        shortcut.access = .appLocal
                    }

                    if let menuItem = shortcut.takenByMainMenu {
                        // TODO: Find a better way to make it possible to dismiss the alert by pressing "Enter". How can we make the input automatically temporarily lose focus while the alert is open?
                        self.blur()

                        NSAlert.showModal(
                            for: self.window,
                            title: String.localizedStringWithFormat("keyboard_shortcut_used_by_menu_item".localized, menuItem.title)
                        )

                        self.focus()

                        return nil
                    }

                    if shortcut.isTakenBySystem {
                        self.blur()

                        let modalResponse = NSAlert.showModal(
                            for: self.window,
                            title: "keyboard_shortcut_used_by_system".localized,
                            // TODO: Add button to offer to open the relevant system settings pane for the user.
                            message: "keyboard_shortcuts_can_be_changed".localized,
                            buttonTitles: [
                                "ok".localized,
                                "force_use_shortcut".localized,
                            ]
                        )

                        self.focus()

                        // If the user has selected "Use Anyway" in the dialog (the second option), we'll continue setting the keyboard shorcut even though it's reserved by the system.
                        guard modalResponse == .alertSecondButtonReturn else {
                            return nil
                        }
                    }

                    self.stringValue = "\(shortcut)"
                    self.showsCancelButton = true

                    self.saveShortcut(shortcut)
                    self.blur()

                    return nil
                }.start()

                return shouldBecomeFirstResponder
            }

            private func saveShortcut(_ shortcut: Shortcut?) {
                setShortcut(shortcut, for: shortcutName)
                if case .reset = onChange?(shortcut) {
                    clear()
                }
            }
        }
    }
#endif
