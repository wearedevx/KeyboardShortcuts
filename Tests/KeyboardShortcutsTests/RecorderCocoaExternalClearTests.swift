#if os(macOS)
    import AppKit
    @preconcurrency @testable import KeyboardShortcuts
    import XCTest

    @MainActor
    final class RecorderCocoaExternalClearTests: XCTestCase {
        func testExplicitAndKeyboardClearRemoveStorageAndNotifyOnceEach() async throws {
            let previousPause = KeyboardShortcuts.isPaused
            defer { KeyboardShortcuts.isPaused = previousPause }
            let (name, shortcut) = try storedShortcut()
            let (deleteName, deleteShortcut) = try storedShortcut()
            defer {
                removeShortcut(name)
                removeShortcut(deleteName)
            }
            var changes: [KeyboardShortcuts.Shortcut?] = []
            var clearCount = 0
            let recorder = KeyboardShortcuts.RecorderCocoa(
                for: name, access: .appLocal, usesNativeClearButton: false,
                onChange: { value, _ in changes.append(value) },
                onClear: { clearCount += 1 }
            )
            let window = ownedWindow(containing: recorder)
            defer { close(window, recorders: [recorder]) }
            XCTAssertEqual(recorder.stringValue, "\(shortcut)")
            try await focus(recorder, in: window)
            XCTAssertTrue(KeyboardShortcuts.isPaused)

            recorder.clearShortcut()

            XCTAssertNil(KeyboardShortcuts.getShortcut(for: name))
            XCTAssertNil(KeyboardShortcuts.defaults.object(forKey: shortcutKey(name)))
            XCTAssertEqual(recorder.stringValue, "")
            XCTAssertEqual(changes.count, 1)
            XCTAssertTrue(changes.allSatisfy { $0 == nil })
            XCTAssertEqual(clearCount, 1)
            XCTAssertFalse(KeyboardShortcuts.isPaused)
            XCTAssertFalse(window.firstResponder === recorder)
            XCTAssertFalse((window.firstResponder as? NSTextView)?.delegate === recorder)
            XCTAssertNil(try searchCell(recorder).cancelButtonCell)

            recorder.shortcutName = deleteName
            XCTAssertEqual(recorder.stringValue, "\(deleteShortcut)")
            try await focus(recorder, in: window)
            NSApplication.shared.sendEvent(try deleteEvent(in: window))

            XCTAssertNil(KeyboardShortcuts.getShortcut(for: deleteName))
            XCTAssertNil(KeyboardShortcuts.defaults.object(forKey: shortcutKey(deleteName)))
            XCTAssertEqual(recorder.stringValue, "")
            XCTAssertEqual(changes.count, 2)
            XCTAssertTrue(changes.allSatisfy { $0 == nil })
            XCTAssertEqual(clearCount, 2)
            XCTAssertFalse(KeyboardShortcuts.isPaused)
            XCTAssertFalse((window.firstResponder as? NSTextView)?.delegate === recorder)
            XCTAssertNil(try searchCell(recorder).cancelButtonCell)
        }

        func testDefaultRecorderRetainsNativeClearCellAcrossStorageRefresh() throws {
            let previousPause = KeyboardShortcuts.isPaused
            defer { KeyboardShortcuts.isPaused = previousPause }
            let (name, shortcut) = try storedShortcut()
            let (replacementName, replacementShortcut) = try storedShortcut()
            defer {
                removeShortcut(name)
                removeShortcut(replacementName)
            }
            let recorder = KeyboardShortcuts.RecorderCocoa(for: name, access: .appLocal)
            let cell = try searchCell(recorder)
            let nativeButton = try XCTUnwrap(cell.cancelButtonCell)
            XCTAssertEqual(recorder.stringValue, "\(shortcut)")

            KeyboardShortcuts.reset(name)
            XCTAssertEqual(recorder.stringValue, "")
            XCTAssertNil(cell.cancelButtonCell)

            recorder.shortcutName = replacementName
            XCTAssertEqual(recorder.stringValue, "\(replacementShortcut)")
            XCTAssertTrue(cell.cancelButtonCell === nativeButton)
        }

        func testExternalClearCellReservesSpaceAcrossStorageAndFocusReset() async throws {
            let previousPause = KeyboardShortcuts.isPaused
            defer { KeyboardShortcuts.isPaused = previousPause }
            let (name, _) = try storedShortcut()
            let (replacementName, _) = try storedShortcut()
            defer {
                removeShortcut(name)
                removeShortcut(replacementName)
            }
            let recorder = KeyboardShortcuts.RecorderCocoa(
                for: name, access: .appLocal, usesNativeClearButton: false
            )
            let nativeRecorder = KeyboardShortcuts.RecorderCocoa(for: name, access: .appLocal)
            let cell = try searchCell(recorder)
            let nativeCell = try searchCell(nativeRecorder)
            let nativeIsBezeled = nativeCell.isBezeled
            let nativeIsBordered = nativeCell.isBordered
            let nativeBezelStyle = nativeCell.bezelStyle
            let nativeFont = nativeCell.font
            let nativeControlSize = nativeCell.controlSize

            func assertNativeAppearance(file: StaticString = #filePath, line: UInt = #line) {
                // Setting isBordered after isBezeled can erase the native rounded bezel.
                for control in [recorder, nativeRecorder] {
                    XCTAssertEqual(control.isBezeled, nativeIsBezeled, file: file, line: line)
                    XCTAssertEqual(control.isBordered, nativeIsBordered, file: file, line: line)
                    XCTAssertEqual(control.bezelStyle, nativeBezelStyle, file: file, line: line)
                    XCTAssertEqual(control.font, nativeFont, file: file, line: line)
                    XCTAssertEqual(control.controlSize, nativeControlSize, file: file, line: line)
                }
                for searchCell in [cell, nativeCell] {
                    XCTAssertEqual(searchCell.isBezeled, nativeIsBezeled, file: file, line: line)
                    XCTAssertEqual(searchCell.isBordered, nativeIsBordered, file: file, line: line)
                    XCTAssertEqual(searchCell.bezelStyle, nativeBezelStyle, file: file, line: line)
                    XCTAssertEqual(searchCell.font, nativeFont, file: file, line: line)
                    XCTAssertEqual(searchCell.controlSize, nativeControlSize, file: file, line: line)
                }
            }

            assertNativeAppearance()
            let frame = CGRect(x: 10, y: 10, width: 180, height: 24)
            recorder.frame = frame
            let populatedRect = cell.searchTextRect(forBounds: recorder.bounds)
            let minimumWidth = recorder.intrinsicContentSize.width
            XCTAssertNil(cell.cancelButtonCell)
            let window = ownedWindow(containing: recorder)
            let nativeWindow = ownedWindow(containing: nativeRecorder)
            defer {
                close(nativeWindow, recorders: [nativeRecorder])
                close(window, recorders: [recorder])
            }
            try await focus(recorder, in: window)
            XCTAssertNil(cell.cancelButtonCell)
            assertNativeAppearance()
            XCTAssertTrue(window.makeFirstResponder(nil))
            XCTAssertFalse(KeyboardShortcuts.isPaused)
            XCTAssertNil(cell.cancelButtonCell)
            assertNativeAppearance()

            KeyboardShortcuts.reset(name)
            let emptyRect = cell.searchTextRect(forBounds: recorder.bounds)
            XCTAssertEqual(recorder.stringValue, "")
            XCTAssertNil(cell.cancelButtonCell)
            XCTAssertEqual(emptyRect.minX, populatedRect.minX, accuracy: 0.01)
            XCTAssertEqual(emptyRect.width - populatedRect.width, 21, accuracy: 0.01)
            XCTAssertEqual(emptyRect.minY, populatedRect.minY, accuracy: 0.01)
            XCTAssertEqual(emptyRect.height, populatedRect.height, accuracy: 0.01)
            XCTAssertEqual(recorder.frame, frame)
            XCTAssertEqual(recorder.intrinsicContentSize.width, minimumWidth)
            XCTAssertGreaterThanOrEqual(minimumWidth, 130)
            XCTAssertEqual(nativeRecorder.stringValue, "")
            assertNativeAppearance()

            try await focus(nativeRecorder, in: nativeWindow)
            assertNativeAppearance()
            XCTAssertTrue(nativeWindow.makeFirstResponder(nil))
            XCTAssertFalse(KeyboardShortcuts.isPaused)
            assertNativeAppearance()

            recorder.shortcutName = replacementName
            nativeRecorder.shortcutName = replacementName
            XCTAssertEqual(cell.searchTextRect(forBounds: recorder.bounds), populatedRect)
            XCTAssertNil(cell.cancelButtonCell)
            XCTAssertEqual(recorder.stringValue, nativeRecorder.stringValue)
            assertNativeAppearance()
        }

        func testClearPreservesAnotherControlsFocus() throws {
            let previousPause = KeyboardShortcuts.isPaused
            defer { KeyboardShortcuts.isPaused = previousPause }
            let (name, _) = try storedShortcut()
            defer { removeShortcut(name) }
            let recorder = KeyboardShortcuts.RecorderCocoa(
                for: name, access: .appLocal, usesNativeClearButton: false
            )
            let window = ownedWindow(containing: recorder)
            defer { close(window, recorders: [recorder]) }
            let otherControl = NSTextField(frame: CGRect(x: 10, y: 60, width: 160, height: 24))
            try XCTUnwrap(window.contentView).addSubview(otherControl)
            XCTAssertTrue(window.makeFirstResponder(otherControl))
            let previousResponder = try XCTUnwrap(window.firstResponder)

            recorder.clearShortcut()

            XCTAssertTrue(window.firstResponder === previousResponder)
            XCTAssertNil(KeyboardShortcuts.getShortcut(for: name))
        }

        func testInactiveRecorderEndAndClearPreserveActiveRecorderOwnership() async throws {
            let previousPause = KeyboardShortcuts.isPaused
            defer { KeyboardShortcuts.isPaused = previousPause }
            let (nameA, _) = try storedShortcut()
            let (nameB, shortcutB) = try storedShortcut()
            defer {
                removeShortcut(nameA)
                removeShortcut(nameB)
            }
            let recorderA = KeyboardShortcuts.RecorderCocoa(
                for: nameA, access: .appLocal, usesNativeClearButton: false
            )
            let recorderB = KeyboardShortcuts.RecorderCocoa(
                for: nameB, access: .appLocal, usesNativeClearButton: false
            )
            let windowA = ownedWindow(containing: recorderA)
            let windowB = ownedWindow(containing: recorderB)
            defer {
                close(windowB, recorders: [recorderB])
                close(windowA, recorders: [recorderA])
            }
            try await focus(recorderB, in: windowB)
            let responderB = try XCTUnwrap(windowB.firstResponder)
            let recordingPlaceholder = recorderB.placeholderString
            XCTAssertTrue(KeyboardShortcuts.isPaused)

            recorderA.endRecording()
            XCTAssertTrue(KeyboardShortcuts.isPaused)
            XCTAssertTrue(windowB.firstResponder === responderB)
            recorderA.clearShortcut()

            XCTAssertNil(KeyboardShortcuts.getShortcut(for: nameA))
            XCTAssertTrue(KeyboardShortcuts.isPaused)
            XCTAssertTrue(windowB.firstResponder === responderB)
            XCTAssertEqual(recorderB.placeholderString, recordingPlaceholder)
            XCTAssertEqual(KeyboardShortcuts.getShortcut(for: nameB), shortcutB)

            // A real event verifies that B's monitor survived operations on inactive A.
            NSApplication.shared.sendEvent(try deleteEvent(in: windowB))
            XCTAssertNil(KeyboardShortcuts.getShortcut(for: nameB))
            XCTAssertFalse(KeyboardShortcuts.isPaused)
        }

        func testCurrentAppLocalResetClearsOnceWithoutRecursiveNilCallback() async throws {
            let previousPause = KeyboardShortcuts.isPaused
            defer { KeyboardShortcuts.isPaused = previousPause }
            let (name, _) = try storedShortcut()
            defer { removeShortcut(name) }
            var changes: [KeyboardShortcuts.Shortcut?] = []
            var clearCount = 0
            let cleared = expectation(description: "Current app-local reset clears once")
            cleared.assertForOverFulfill = true
            let recursiveChange = expectation(description: "Nil callback reset must not clear recursively")
            recursiveChange.isInverted = true
            let recorder = KeyboardShortcuts.RecorderCocoa(
                for: name, access: .appLocal, usesNativeClearButton: false,
                onChange: { value, post in
                    changes.append(value)
                    if changes.count > 2 {
                        recursiveChange.fulfill()
                    }
                    // Exercise both the current value reset and a reset requested for nil.
                    post(.reset)
                },
                onClear: {
                    clearCount += 1
                    cleared.fulfill()
                }
            )
            let window = ownedWindow(containing: recorder)
            defer { close(window, recorders: [recorder]) }
            let originalFrame = recorder.frame
            try await focus(recorder, in: window)
            XCTAssertTrue(KeyboardShortcuts.isPaused)
            let characters = String(try XCTUnwrap(UnicodeScalar(UInt32(NSF19FunctionKey))))
            let recordEvent = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [.function], timestamp: 0,
                windowNumber: window.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: 80
            ))

            NSApplication.shared.sendEvent(recordEvent)

            XCTAssertEqual(changes.count, 1, "Reset must be deferred until recording finishes")
            let recordedShortcut = try XCTUnwrap(changes.first ?? nil)
            XCTAssertEqual(recordedShortcut.access, .appLocal)
            // App-local recording removes storage and can refresh the display to empty.
            // Reset must use change/session identity, not persisted or displayed equality.
            XCTAssertNil(KeyboardShortcuts.getShortcut(for: name))
            XCTAssertNil(KeyboardShortcuts.defaults.object(forKey: shortcutKey(name)))

            await fulfillment(of: [cleared], timeout: 1)
            await fulfillment(of: [recursiveChange], timeout: 0.1)

            XCTAssertEqual(changes.count, 2)
            XCTAssertEqual(changes.first ?? nil, recordedShortcut)
            XCTAssertNil(changes.last ?? nil)
            XCTAssertEqual(clearCount, 1)
            XCTAssertEqual(recorder.stringValue, "")
            XCTAssertNil(KeyboardShortcuts.getShortcut(for: name))
            XCTAssertNil(KeyboardShortcuts.defaults.object(forKey: shortcutKey(name)))
            XCTAssertFalse(KeyboardShortcuts.isPaused)
            XCTAssertFalse(window.firstResponder === recorder)
            XCTAssertFalse((window.firstResponder as? NSTextView)?.delegate === recorder)
            XCTAssertNil(try searchCell(recorder).cancelButtonCell)
            XCTAssertEqual(recorder.frame, originalFrame)
            XCTAssertTrue(recorder.window === window)
            XCTAssertFalse(window.isKeyWindow)
        }

        func testNewRecorderInvalidatesResetForSameUnpersistedShortcut() async throws {
            func recordingState(_ recorder: KeyboardShortcuts.RecorderCocoa, in window: NSWindow) -> String {
                "paused=\(KeyboardShortcuts.isPaused), placeholder=\(recorder.placeholderString ?? "nil"), "
                    + "recorderResponder=\(window.firstResponder === recorder), "
                    + "editorDelegate=\((window.firstResponder as? NSTextView)?.delegate === recorder), "
                    + "responder=\(window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil")"
            }
            let previousPause = KeyboardShortcuts.isPaused
            defer { KeyboardShortcuts.isPaused = previousPause }
            let (name, _) = try storedShortcut()
            defer { removeShortcut(name) }
            let staleClear = expectation(description: "Old recorder must not clear after replacement recording")
            staleClear.isInverted = true
            var changesA: [KeyboardShortcuts.Shortcut?] = []
            var clearCountA = 0
            var capturedPostA: ((KeyboardShortcuts.PostOnChange) -> Void)?
            let recorderA = KeyboardShortcuts.RecorderCocoa(
                for: name, access: .appLocal, usesNativeClearButton: false,
                onChange: { value, post in
                    changesA.append(value)
                    if value != nil {
                        capturedPostA = post
                    } else {
                        staleClear.fulfill()
                    }
                },
                onClear: {
                    clearCountA += 1
                    staleClear.fulfill()
                }
            )
            let windowA = ownedWindow(containing: recorderA)
            defer { close(windowA, recorders: [recorderA]) }
            try await focus(recorderA, in: windowA)
            let characters = String(try XCTUnwrap(UnicodeScalar(UInt32(NSF19FunctionKey))))
            let eventA = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [.function], timestamp: 0,
                windowNumber: windowA.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: 80
            ))
            NSApplication.shared.sendEvent(eventA)
            let postA = try XCTUnwrap(capturedPostA)
            let shortcutA = try XCTUnwrap(changesA.first ?? nil)
            XCTAssertEqual(changesA.count, 1)
            XCTAssertEqual(shortcutA.access, .appLocal)
            XCTAssertNil(KeyboardShortcuts.getShortcut(for: name))
            XCTAssertNil(KeyboardShortcuts.defaults.object(forKey: shortcutKey(name)))

            var changesB: [KeyboardShortcuts.Shortcut?] = []
            var clearCountB = 0
            let recorderB = KeyboardShortcuts.RecorderCocoa(
                for: name, access: .appLocal, usesNativeClearButton: false,
                onChange: { value, _ in changesB.append(value) },
                onClear: { clearCountB += 1 }
            )
            let windowB = ownedWindow(containing: recorderB)
            defer { close(windowB, recorders: [recorderB]) }
            let originalFrameB = recorderB.frame
            XCTAssertEqual(recorderB.stringValue, "")
            try await focus(recorderB, in: windowB)
            let eventB = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [.function], timestamp: 0,
                windowNumber: windowB.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: 80
            ))
            NSApplication.shared.sendEvent(eventB)
            let shortcutB = try XCTUnwrap(changesB.first ?? nil)
            XCTAssertEqual(changesB.count, 1)
            XCTAssertEqual(shortcutB, shortcutA)
            XCTAssertEqual(shortcutB.access, .appLocal)
            XCTAssertEqual(recorderB.stringValue, "\(shortcutB)")
            // Storage was already nil before B recorded, so no persistence update
            // can notify A that its same-value reset callback is now stale.
            XCTAssertNil(KeyboardShortcuts.getShortcut(for: name))
            XCTAssertNil(KeyboardShortcuts.defaults.object(forKey: shortcutKey(name)))
            let pauseBeforeStaleReset = KeyboardShortcuts.isPaused
            XCTAssertFalse(
                pauseBeforeStaleReset,
                "Accepted B recording must finish before stale reset. "
                    + "A: \(recordingState(recorderA, in: windowA)); B: \(recordingState(recorderB, in: windowB))"
            )

            postA(.reset)
            await fulfillment(of: [staleClear], timeout: 0.1)

            XCTAssertEqual(changesA.count, 1)
            XCTAssertEqual(changesA.first ?? nil, shortcutA)
            XCTAssertEqual(clearCountA, 0)
            XCTAssertEqual(changesB.count, 1)
            XCTAssertEqual(changesB.first ?? nil, shortcutB)
            XCTAssertEqual(clearCountB, 0)
            XCTAssertEqual(recorderB.stringValue, "\(shortcutB)")
            XCTAssertNil(KeyboardShortcuts.getShortcut(for: name))
            XCTAssertNil(KeyboardShortcuts.defaults.object(forKey: shortcutKey(name)))
            XCTAssertEqual(
                KeyboardShortcuts.isPaused, pauseBeforeStaleReset,
                "Stale reset must not change recording ownership or pause state"
            )
            XCTAssertFalse(
                KeyboardShortcuts.isPaused,
                "A: \(recordingState(recorderA, in: windowA)); B: \(recordingState(recorderB, in: windowB))"
            )
            XCTAssertEqual(recorderB.frame, originalFrameB)
            XCTAssertTrue(recorderB.window === windowB)
            XCTAssertFalse(windowA.isKeyWindow)
            XCTAssertFalse(windowB.isKeyWindow)
        }

        func testStaleResetCannotClearSameValueReplacementOrNewRecordingSession() async throws {
            let previousPause = KeyboardShortcuts.isPaused
            defer { KeyboardShortcuts.isPaused = previousPause }
            let (name, _) = try storedShortcut()
            defer { removeShortcut(name) }
            var capturedPost: ((KeyboardShortcuts.PostOnChange) -> Void)?
            var recordedShortcut: KeyboardShortcuts.Shortcut?
            var changeCount = 0
            var forbiddenClear: XCTestExpectation?
            let recorder = KeyboardShortcuts.RecorderCocoa(
                for: name, access: .appLocal, usesNativeClearButton: false,
                onChange: { value, post in
                    changeCount += 1
                    if let value {
                        recordedShortcut = value
                        capturedPost = post
                    } else {
                        forbiddenClear?.fulfill()
                    }
                }
            )
            let window = ownedWindow(containing: recorder)
            defer { close(window, recorders: [recorder]) }
            try await focus(recorder, in: window)
            let characters = String(try XCTUnwrap(UnicodeScalar(UInt32(NSF19FunctionKey))))
            let recordEvent = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [.function], timestamp: 0,
                windowNumber: window.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: 80
            ))
            NSApplication.shared.sendEvent(recordEvent)
            let post = try XCTUnwrap(capturedPost)
            let shortcut = try XCTUnwrap(recordedShortcut)
            XCTAssertEqual(shortcut.access, .appLocal)
            XCTAssertEqual(changeCount, 1)

            // A newer notification invalidates the callback even when the value is identical.
            let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(shortcut), encoding: .utf8))
            KeyboardShortcuts.defaults.set(encoded, forKey: shortcutKey(name))
            KeyboardShortcuts.userDefaultsDidChange(name: name)
            let replacementCleared = expectation(description: "Stale reset cannot clear replacement")
            replacementCleared.isInverted = true
            forbiddenClear = replacementCleared
            post(.reset)
            await fulfillment(of: [replacementCleared], timeout: 0.1)
            XCTAssertEqual(KeyboardShortcuts.getShortcut(for: name), shortcut)
            XCTAssertEqual(recorder.stringValue, "\(shortcut)")
            XCTAssertEqual(changeCount, 1)

            // Capture a fresh callback to exercise session invalidation independently.
            try await focus(recorder, in: window)
            NSApplication.shared.sendEvent(recordEvent)
            let sessionPost = try XCTUnwrap(capturedPost)
            XCTAssertEqual(changeCount, 2)
            KeyboardShortcuts.defaults.set(encoded, forKey: shortcutKey(name))
            try await focus(recorder, in: window)
            let currentResponder = try XCTUnwrap(window.firstResponder)
            let sessionCleared = expectation(description: "Stale reset cannot clear new session")
            sessionCleared.isInverted = true
            forbiddenClear = sessionCleared
            sessionPost(.reset)
            await fulfillment(of: [sessionCleared], timeout: 0.1)
            XCTAssertEqual(KeyboardShortcuts.getShortcut(for: name), shortcut)
            XCTAssertEqual(changeCount, 2)
            XCTAssertTrue(window.firstResponder === currentResponder)
            XCTAssertTrue(KeyboardShortcuts.isPaused)
        }

        func testPlainOverlayButtonReceivesMouseUpAndClearsOnce() async throws {
            let previousPause = KeyboardShortcuts.isPaused
            defer { KeyboardShortcuts.isPaused = previousPause }
            let (name, _) = try storedShortcut()
            defer { removeShortcut(name) }
            var changeCount = 0
            var clearCount = 0
            let recorder = KeyboardShortcuts.RecorderCocoa(
                for: name, access: .appLocal, usesNativeClearButton: false,
                onChange: { value, _ in
                    XCTAssertNil(value)
                    changeCount += 1
                },
                onClear: { clearCount += 1 }
            )
            let window = MouseReleaseWindow(
                contentRect: CGRect(x: -10_000, y: -10_000, width: 240, height: 120),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            recorder.frame = CGRect(x: 10, y: 10, width: 180, height: 24)
            try XCTUnwrap(window.contentView).addSubview(recorder)
            defer { close(window, recorders: [recorder]) }
            let clicked = expectation(description: "Overlay button receives mouse release")
            clicked.assertForOverFulfill = true
            let target = ClearButtonTarget(recorder: recorder, onAction: { clicked.fulfill() })
            let button = FirstMouseButton(
                frame: CGRect(x: recorder.frame.maxX - 21, y: recorder.frame.minY, width: 21, height: 24)
            )
            button.title = "×"
            button.isBordered = false
            button.target = target
            button.action = #selector(ClearButtonTarget.clear(_:))
            button.sendAction(on: .leftMouseUp)
            try XCTUnwrap(window.contentView).addSubview(button)
            window.orderFront(nil)
            XCTAssertFalse(window.isKeyWindow)
            try await focus(recorder, in: window)
            let originalFrame = recorder.frame
            let point = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
            XCTAssertTrue(window.contentView?.hitTest(point) === button)
            let down = try XCTUnwrap(NSEvent.mouseEvent(
                with: .leftMouseDown, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1
            ))
            let up = try XCTUnwrap(NSEvent.mouseEvent(
                with: .leftMouseUp, location: point, modifierFlags: [],
                timestamp: down.timestamp + 0.01,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 2, clickCount: 1, pressure: 0
            ))
            let released = expectation(description: "Owned mouse-up passes through local event monitoring")
            released.assertForOverFulfill = true
            let releaseMonitor = try XCTUnwrap(NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
                if event.windowNumber == up.windowNumber,
                   event.eventNumber == up.eventNumber,
                   event.timestamp == up.timestamp {
                    released.fulfill()
                }
                return event
            })
            defer { NSEvent.removeMonitor(releaseMonitor) }

            // Native NSButton tracking reads its release without application dispatch.
            // Deliver through the application while tracking, then our owned window
            // queues the surviving event for the native button's tracking loop.
            window.pendingRelease = up
            RunLoop.main.perform(inModes: [.eventTracking]) {
                // This block runs only on the main run loop's native tracking mode.
                MainActor.assumeIsolated {
                    guard let release = window.pendingRelease else { return }
                    NSApplication.shared.sendEvent(release)
                    if window.releaseCount == 0 {
                        XCTFail("Recorder monitor must pass the release to the owned window")
                        // Unblock tracking on failure; the delivery assertion still fails.
                        NSApplication.shared.postEvent(release, atStart: true)
                    }
                }
            }
            window.sendEvent(down)
            window.pendingRelease = nil
            XCTAssertEqual(button.mouseDownCount, 1, "Owned window must deliver the press to its overlay")
            await fulfillment(of: [released, clicked], timeout: 1)

            XCTAssertEqual(window.releaseCount, 1)
            XCTAssertEqual(target.actionCount, 1)
            XCTAssertEqual(changeCount, 1)
            XCTAssertEqual(clearCount, 1)
            XCTAssertNil(KeyboardShortcuts.getShortcut(for: name))
            XCTAssertNil(KeyboardShortcuts.defaults.object(forKey: shortcutKey(name)))
            XCTAssertEqual(recorder.stringValue, "")
            XCTAssertFalse(KeyboardShortcuts.isPaused)
            XCTAssertNil(try searchCell(recorder).cancelButtonCell)
            XCTAssertEqual(recorder.frame, originalFrame)
            XCTAssertFalse(window.isKeyWindow)
        }

        private func storedShortcut() throws -> (KeyboardShortcuts.Name, KeyboardShortcuts.Shortcut) {
            // SwiftPM's XCTest host may not have created an AppKit application yet.
            _ = NSApplication.shared
            // Fail before any write if XCTest isolation was not installed.
            XCTAssertTrue(KeyboardShortcuts.defaults !== UserDefaults.standard)
            guard KeyboardShortcuts.defaults !== UserDefaults.standard else {
                throw XCTSkip("Shortcut tests require isolated preferences")
            }
            let name = KeyboardShortcuts.Name("RecorderCocoaExternalClearTests.\(UUID().uuidString)")
            var shortcut = KeyboardShortcuts.Shortcut(.k, modifiers: [.command, .shift])
            shortcut.access = .appLocal
            // setShortcut removes app-local values, so seed this persisted fixture directly.
            let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(shortcut), encoding: .utf8))
            KeyboardShortcuts.defaults.set(encoded, forKey: shortcutKey(name))
            let domain = "KeyboardShortcuts.tests.\(ProcessInfo.processInfo.processIdentifier)"
            XCTAssertEqual(
                KeyboardShortcuts.defaults.persistentDomain(forName: domain)?[shortcutKey(name)] as? String,
                encoded
            )
            XCTAssertEqual(KeyboardShortcuts.getShortcut(for: name), shortcut)
            return (name, shortcut)
        }

        private func shortcutKey(_ name: KeyboardShortcuts.Name) -> String {
            "KeyboardShortcuts_\(name.rawValue)"
        }

        private func removeShortcut(_ name: KeyboardShortcuts.Name) {
            KeyboardShortcuts.reset(name)
            KeyboardShortcuts.defaults.removeObject(forKey: shortcutKey(name))
        }

        private func searchCell(_ recorder: KeyboardShortcuts.RecorderCocoa) throws -> NSSearchFieldCell {
            try XCTUnwrap(recorder.cell as? NSSearchFieldCell)
        }

        private func ownedWindow(containing recorder: KeyboardShortcuts.RecorderCocoa) -> NSWindow {
            _ = NSApplication.shared
            let window = NSWindow(
                contentRect: CGRect(x: -10_000, y: -10_000, width: 240, height: 120),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            if recorder.frame.isEmpty {
                recorder.frame = CGRect(x: 10, y: 10, width: 180, height: 24)
            }
            window.contentView?.addSubview(recorder)
            return window
        }

        private func close(_ window: NSWindow, recorders: [KeyboardShortcuts.RecorderCocoa]) {
            for recorder in recorders {
                recorder.endRecording()
            }
            window.makeFirstResponder(nil)
            for recorder in recorders {
                recorder.removeFromSuperview()
            }
            window.orderOut(nil)
            window.close()
        }

        private func focus(_ recorder: KeyboardShortcuts.RecorderCocoa, in window: NSWindow) async throws {
            // Use APIs available on the fork's macOS 10.15 deployment target.
            let deadline = Date().addingTimeInterval(1)
            while !recorder.canBecomeKeyView, Date() < deadline {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTAssertTrue(recorder.canBecomeKeyView, "Recorder must become focusable after window attachment")
            XCTAssertTrue(window.makeFirstResponder(recorder))
        }

        private func deleteEvent(in window: NSWindow) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil,
                characters: "\u{7F}", charactersIgnoringModifiers: "\u{7F}",
                isARepeat: false, keyCode: 51
            ))
        }

        @MainActor
        private final class MouseReleaseWindow: NSWindow {
            private(set) var releaseCount = 0
            var pendingRelease: NSEvent?

            override func sendEvent(_ event: NSEvent) {
                guard event.type == .leftMouseUp else {
                    super.sendEvent(event)
                    return
                }
                releaseCount += 1
                NSApplication.shared.postEvent(event, atStart: true)
            }
        }

        @MainActor
        private final class FirstMouseButton: NSButton {
            private(set) var mouseDownCount = 0
            // Match an overlay that accepts the click without activating its window.
            override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

            override func mouseDown(with event: NSEvent) {
                mouseDownCount += 1
                super.mouseDown(with: event)
            }
        }

        @MainActor
        private final class ClearButtonTarget: NSObject {
            let recorder: KeyboardShortcuts.RecorderCocoa
            private let onAction: () -> Void
            private(set) var actionCount = 0

            init(recorder: KeyboardShortcuts.RecorderCocoa, onAction: @escaping () -> Void) {
                self.recorder = recorder
                self.onAction = onAction
            }

            @objc func clear(_ sender: NSButton) {
                actionCount += 1
                recorder.clearShortcut()
                onAction()
            }
        }
    }
#endif
