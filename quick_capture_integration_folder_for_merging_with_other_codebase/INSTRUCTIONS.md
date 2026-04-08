# Quick Capture — Integration Instructions for AI Agent

## Feature Summary
Adds a global floating capture widget to a macOS SwiftUI app. The user double-presses the **Control key** from any app to open a small animated panel. They can then:
- **Drag** links, images, or text onto it
- **Copy** anything (text, URL) while it's open — auto-captured
- **Screenshot** with ⌘⇧4 or ⌘⌃⇧4 — auto-captured
- The panel is **invisible in screenshots** (excluded via `sharingType = .none`)
- All content is funnelled into the **existing canvas pipeline** — no new parsing logic

---

## Files in This Folder

| File | Status | Action Required |
|------|--------|-----------------|
| `Controllers/QuickCaptureController.swift` | **NEW** | Add to Xcode target |
| `Views/QuickCaptureView.swift` | **NEW** | Add to Xcode target |
| `CanvasAiApp.swift` | **MODIFIED** | Merge changes (see below) |
| `ContentView.swift` | **MODIFIED** | Merge changes (see below) |
| `Info.plist` | **MODIFIED** | Merge one key (see below) |
| `CanvasAi.entitlements` | **MODIFIED** | Merge one value (see below) |

---

## Step-by-Step Integration

### 1. Add the two new files to the Xcode project
- `Controllers/QuickCaptureController.swift` → add to your Xcode target
- `Views/QuickCaptureView.swift` → add to your Xcode target
- In Xcode: right-click the appropriate group → "Add Files to [target]…" → tick "Add to targets"

### 2. Adapt type/method names in the new files
Both new files have a comment block at the top listing every dependency. Search for these names and replace if your repo uses different names:

| Name in these files | What it is | Check your repo |
|---------------------|-----------|-----------------|
| `CanvasViewModel` | Main `@Observable` view-model class | Must be `@Observable` (not `ObservableObject`) for `.environment()` injection to work |
| `viewModel.addNode(type:content:)` | Creates a canvas node + posts to backend | Signature: `func addNode(type: ItemType, content: String, position: CGPoint? = nil)` |
| `PasteboardService.readPasteboard()` | Returns `(type: ItemType, content: String)?` from clipboard | Static method |
| `PasteboardService.processDropProviders(_:)` | Async, returns `[(type: ItemType, content: String)]` from `[NSItemProvider]` | Static method |
| `CanvasItem.ItemType` | Enum with cases `.text`, `.image`, `.link`, `.drawing` | Used in switch statements |
| `Color.terracotta` | Brand accent colour (`#DE7356`) | Define as `extension Color` if missing |

### 3. Merge CanvasAiApp.swift
Do NOT replace your App file wholesale — only add these pieces:

```swift
// Add these two @State properties to your App struct:
@State private var viewModel = YourViewModelType()     // LIFT from ContentView if it's there
@State private var captureController: QuickCaptureController?

// In your WindowGroup, pass viewModel to ContentView:
ContentView(viewModel: viewModel)
    .onAppear {
        if captureController == nil {
            captureController = QuickCaptureController(viewModel: viewModel)
            captureController?.setup()
        }
    }

// Add to your Notification.Name extension (create one if it doesn't exist):
static let quickCaptureWillShow           = Notification.Name("quickCaptureWillShow")
static let quickCaptureDidHide            = Notification.Name("quickCaptureDidHide")
static let quickCapturePasteboardCaptured = Notification.Name("quickCapturePasteboardCaptured")
```

### 4. Merge ContentView.swift
**One line change only.** Find where ContentView declares its view-model and change it from owning it to accepting it as a parameter:

```swift
// BEFORE (remove this):
@State private var viewModel = YourViewModelType()

// AFTER (replace with):
var viewModel: YourViewModelType
```

Everything else in ContentView is unchanged.

### 5. Merge Info.plist
Add this key inside the root `<dict>` (alongside your existing usage descriptions):

```xml
<key>NSAccessibilityUsageDescription</key>
<string>CosmosCanvas uses Accessibility to detect the double-Control shortcut system-wide, so you can capture content from any app.</string>
```

### 6. Merge entitlements file
Change sandbox to false (required so the app can read screenshot files from Desktop):

```xml
<key>com.apple.security.app-sandbox</key>
<false/>
```

Note: Calendar, network, and any other entitlements stay unchanged. Only the sandbox line changes.

---

## Runtime Requirements
- **First launch**: macOS will show a system dialog for **Accessibility** access. The user must grant it in System Settings → Privacy & Security → Accessibility, then restart the app.
- **After granting**: double-pressing Control from any app opens the panel.

---

## How It Works (for debugging)

```
User double-presses Control
    → QuickCaptureController.startHotkeyMonitors() detects two .flagsChanged
      events within 350ms where modifierFlags contains .control
    → showPanel() → orderFrontRegardless() → posts .quickCaptureWillShow
    → QuickCaptureView receives notification → startBloom() animation

While panel is open, QuickCaptureController polls NSPasteboard every 0.4s:
    → If changeCount changes:
        • Try NSImage (handles ⌘⇧4 file screenshots + ⌘⌃⇧4 clipboard screenshots)
        • Fall back to PasteboardService.readPasteboard() for text/links
    → Calls viewModel.addNode() → posts .quickCapturePasteboardCaptured
    → QuickCaptureView shows success state → controller auto-dismisses after 1.5s

User drags content onto panel:
    → QuickCaptureView.handleDrop() → PasteboardService.processDropProviders()
    → viewModel.addNode() for each item → success state → auto-dismiss

Dismiss triggers: Escape key, double-Control again, or auto after capture
No click-outside dismiss (intentional — lets user take screenshots freely)
```
