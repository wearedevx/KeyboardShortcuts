#if os(macOS)
    import SwiftUI

    extension KeyboardShortcuts {
        private struct _Recorder: NSViewRepresentable { // swiftlint:disable:this type_name
            typealias NSViewType = RecorderCocoa

            let name: Name
            let access: KeyboardShortcuts.Access
            let onChange: ((_ shortcut: Shortcut?) -> PostOnChange)?

            func makeNSView(context _: Context) -> NSViewType {
                .init(for: name, access: access, onChange: onChange)
            }

            func updateNSView(_ nsView: NSViewType, context _: Context) {
                nsView.shortcutName = name
            }
        }

        /**
         A SwiftUI `View` that lets the user record a keyboard shortcut.

         You would usually put this in your settings window.

         It automatically prevents choosing a keyboard shortcut that is already taken by the system or by the app's main menu by showing a user-friendly alert to the user.

         It takes care of storing the keyboard shortcut in `UserDefaults` for you.

         ```swift
         import SwiftUI
         import KeyboardShortcuts

         struct SettingsScreen: View {
         	var body: some View {
         		Form {
         			KeyboardShortcuts.Recorder("Toggle Unicorn Mode:", name: .toggleUnicornMode)
         		}
         	}
         }
         ```
         */
        public struct Recorder<Label: View>: View { // swiftlint:disable:this type_name
            private let name: Name
            private let access: KeyboardShortcuts.Access
            private let onChange: ((Shortcut?) -> PostOnChange)?
            private let hasLabel: Bool
            private let label: Label

            init(
                for name: Name,
                access: KeyboardShortcuts.Access = .systemGlobal,
                onChange: ((Shortcut?) -> PostOnChange)? = nil,
                hasLabel: Bool,
                @ViewBuilder label: () -> Label
            ) {
                self.name = name
                self.access = access
                self.onChange = onChange
                self.hasLabel = hasLabel
                self.label = label()
            }

            public var body: some View {
                if hasLabel {
                    if #available(macOS 13, *) {
                        LabeledContent {
                            _Recorder(
                                name: name,
                                access: access,
                                onChange: onChange
                            )
                        } label: {
                            label
                        }
                    } else {
                        _Recorder(
                            name: name,
                            access: access,
                            onChange: onChange
                        )
                        .formLabel {
                            label
                        }
                    }
                } else {
                    _Recorder(
                        name: name,
                        access: access,
                        onChange: onChange
                    )
                }
            }
        }
    }

    public extension KeyboardShortcuts.Recorder<EmptyView> {
        /**
         - Parameter name: Strongly-typed keyboard shortcut name.
         - Parameter onChange: Callback which will be called when the keyboard shortcut is changed/removed by the user. This can be useful when you need more control. For example, when migrating from a different keyboard shortcut solution and you need to store the keyboard shortcut somewhere yourself instead of relying on the built-in storage. However, it's strongly recommended to just rely on the built-in storage when possible.
         */
        init(
            for name: KeyboardShortcuts.Name,
            access _: KeyboardShortcuts.Access = .systemGlobal,
            onChange: ((KeyboardShortcuts.Shortcut?) -> KeyboardShortcuts.PostOnChange)? = nil
        ) {
            self.init(
                for: name,
                onChange: onChange,
                hasLabel: false
            ) {}
        }
    }

    public extension KeyboardShortcuts.Recorder<Text> {
        /**
         - Parameter title: The title of the keyboard shortcut recorder, describing its purpose.
         - Parameter name: Strongly-typed keyboard shortcut name.
         - Parameter onChange: Callback which will be called when the keyboard shortcut is changed/removed by the user. This can be useful when you need more control. For example, when migrating from a different keyboard shortcut solution and you need to store the keyboard shortcut somewhere yourself instead of relying on the built-in storage. However, it's strongly recommended to just rely on the built-in storage when possible.
         */
        init(
            _ title: LocalizedStringKey,
            name: KeyboardShortcuts.Name,
            access: KeyboardShortcuts.Access = .systemGlobal,
            onChange: ((KeyboardShortcuts.Shortcut?) -> KeyboardShortcuts.PostOnChange)? = nil
        ) {
            self.init(
                for: name,
                access: access,
                onChange: onChange,
                hasLabel: true
            ) {
                Text(title)
            }
        }
    }

    public extension KeyboardShortcuts.Recorder<Text> {
        /**
         - Parameter title: The title of the keyboard shortcut recorder, describing its purpose.
         - Parameter name: Strongly-typed keyboard shortcut name.
         - Parameter onChange: Callback which will be called when the keyboard shortcut is changed/removed by the user. This can be useful when you need more control. For example, when migrating from a different keyboard shortcut solution and you need to store the keyboard shortcut somewhere yourself instead of relying on the built-in storage. However, it's strongly recommended to just rely on the built-in storage when possible.
         */
        @_disfavoredOverload
        init(
            _ title: String,
            name: KeyboardShortcuts.Name,
            access _: KeyboardShortcuts.Access = .systemGlobal,
            onChange: ((KeyboardShortcuts.Shortcut?) -> KeyboardShortcuts.PostOnChange)? = nil
        ) {
            self.init(
                for: name,
                onChange: onChange,
                hasLabel: true
            ) {
                Text(title)
            }
        }
    }

    public extension KeyboardShortcuts.Recorder {
        /**
         - Parameter name: Strongly-typed keyboard shortcut name.
         - Parameter onChange: Callback which will be called when the keyboard shortcut is changed/removed by the user. This can be useful when you need more control. For example, when migrating from a different keyboard shortcut solution and you need to store the keyboard shortcut somewhere yourself instead of relying on the built-in storage. However, it's strongly recommended to just rely on the built-in storage when possible.
         - Parameter label: A view that describes the purpose of the keyboard shortcut recorder.
         */
        init(
            for name: KeyboardShortcuts.Name,
            access _: KeyboardShortcuts.Access = .systemGlobal,
            onChange: ((KeyboardShortcuts.Shortcut?) -> KeyboardShortcuts.PostOnChange)? = nil,
            @ViewBuilder label: () -> Label
        ) {
            self.init(
                for: name,
                onChange: onChange,
                hasLabel: true,
                label: label
            )
        }
    }

    #Preview {
        KeyboardShortcuts.Recorder("record_shortcut", name: .init("xcodePreview"))
            .environment(\.locale, .init(identifier: "en"))
    }

    #Preview {
        KeyboardShortcuts.Recorder("record_shortcut", name: .init("xcodePreview"))
            .environment(\.locale, .init(identifier: "zh-Hans"))
    }

    #Preview {
        KeyboardShortcuts.Recorder("record_shortcut", name: .init("xcodePreview"))
            .environment(\.locale, .init(identifier: "ru"))
    }
#endif
