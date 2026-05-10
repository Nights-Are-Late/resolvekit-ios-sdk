# ResolveKit Project Detection Reference

## Quick Detection Script

When an agent needs to determine how to integrate ResolveKit, run through these checks in order:

### 1. Root Directory Scan

Check for these files/directories at the project root:

| File/Directory | Indicates |
|---|---|
| `*.xcodeproj/` or `*.xcworkspace/` | iOS/macOS project |
| `Package.swift` | Swift package (could be iOS or macOS) |
| `build.gradle.kts` or `build.gradle` | Android or multi-platform |
| `settings.gradle.kts` or `settings.gradle` | Android project |
| `android/` directory | Android module |
| `ios/` directory | iOS module |

### 2. iOS Deep Detection

If iOS is detected, check:

```bash
# SwiftUI app
grep -r "struct.*: App" --include="*.swift" . | head -5

# UIKit app
grep -r "UIApplicationDelegate" --include="*.swift" . | head -5
grep -r "application:didFinishLaunchingWithOptions" --include="*.swift" . | head -5

# macOS app
grep -r "NSApplicationDelegate" --include="*.swift" . | head -5

# Check existing dependencies
grep -r "dependencies:" Package.swift 2>/dev/null
```

Determine UI framework:
- **SwiftUI**: Files with `import SwiftUI`, `@main` struct with `App`, `View` protocol
- **UIKit**: `UIViewController`, `AppDelegate`, `UIWindowScene`
- **AppKit**: `NSViewController`, `NSApplicationDelegate`

### 3. Android Deep Detection

If Android is detected, check:

```bash
# Check for Compose
grep -r "setContent" --include="*.kt" app/src/main/ | head -5
grep -r "@Composable" --include="*.kt" app/src/main/ | head -5
grep -r "androidx.compose" --include="*.kt" app/src/main/ | head -5

# Check for View-based
grep -r "setContentView" --include="*.kt" --include="*.java" app/src/main/ | head -5
grep -r "\.xml" app/src/main/res/layout/ 2>/dev/null | head -5

# Check DI framework
grep -r "@HiltAndroidApp" --include="*.kt" . | head -3  # Hilt
grep -r "KoinApplication" --include="*.kt" . | head -3  # Koin
grep -r "@Component" --include="*.kt" . | head -3  # Dagger
```

Determine UI framework:
- **Compose**: `setContent {}`, `@Composable` annotations, `androidx.compose.*` imports
- **View-based**: `setContentView(R.layout.*)`, XML layouts in `res/layout/`
- **Mixed**: Both patterns present

### 4. Architecture Pattern Detection

```bash
# MVVM (iOS)
grep -r "ObservableObject" --include="*.swift" . | head -3
grep -r "class.*ViewModel" --include="*.swift" . | head -3

# MVVM (Android)
grep -r "class.*ViewModel" --include="*.kt" . | head -3
grep -r "by viewModels" --include="*.kt" . | head -3

# Clean Architecture
find . -type d -name "domain" -o -name "usecase" -o -name "usecases" 2>/dev/null | head -5
find . -type d -name "data" -o -name "repository" -o -name "repositories" 2>/dev/null | head -5
find . -type d -name "presentation" -o -name "ui" -o -name "screens" 2>/dev/null | head -5

# State management
grep -r "@Published" --include="*.swift" . | head -3  # Combine
grep -r "StateFlow" --include="*.kt" . | head -3  # Kotlin Flows
```

### 5. Backend Detection

```bash
# Check if this IS the backend
test -f "agent/main.py" && echo "ResolveKit backend repo"
test -f "knowledge_bases/main.py" && echo "ResolveKit backend repo"
test -f "docker-compose.yml" && grep -q "resolvekit" docker-compose.yml 2>/dev/null

# Check for FastAPI backend
grep -r "from fastapi" --include="*.py" . | head -3
grep -r "IAA_" --include="*.env" . | head -3

# Check for Docker Compose
test -f "docker-compose.yml" && echo "Docker Compose detected"
```

## Decision Matrix

| Detected | UI Framework | Architecture | Integration Approach |
|---|---|---|---|
| iOS + SwiftUI | SwiftUI | MVVM | `@StateObject` runtime, inline chat |
| iOS + UIKit | UIKit | Traditional | Service-based runtime, push VC |
| iOS + AppKit | AppKit | Traditional | `presentAsModalWindow` |
| Android + Compose | Compose | MVVM | ViewModel runtime, inline chat |
| Android + Views | XML | Traditional | Activity/Fragment surfaces |
| Android + Mixed | Compose+Views | Hilt+MVVM | Mixed approach, DI runtime |
| Backend repo | N/A | FastAPI | Docker Compose, env config |
| Mono-repo | Both | Clean | Platform-specific, shared backend |
