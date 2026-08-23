# Project Documentation and GitHub Pages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make SeamCarvingSwift understandable to a new user by expanding the README, adding complete project documentation, and publishing a dependency-free static documentation site from `docs/` on GitHub Pages.

**Architecture:** Keep Markdown as the canonical documentation source and add a small static HTML shell under `docs/` for GitHub Pages. The README is the onboarding entry point; the detailed pages explain architecture, algorithm principles, Swift APIs, CLI workflows, and the iPhone/iPad/Mac Catalyst app. Do not add a Node, Python, Jekyll, or MkDocs runtime dependency.

**Tech Stack:** Markdown, semantic HTML, CSS, vanilla JavaScript only for navigation/theme behavior, Swift 6 package APIs, `swift-argument-parser`, SwiftUI, UIKit, Mac Catalyst, Accelerate, Metal, Vision.

**Spec:** The approved in-chat design: update `README.md`; add architecture, principles, API, CLI, and app guides; provide a static `docs/index.html` and shared CSS suitable for GitHub Pages.

## Global Constraints

- Document only capabilities present in the repository; distinguish implemented, optional, and unsupported behavior.
- State that Mac support is Mac Catalyst through the unified iOS target, not a separate native AppKit target.
- Keep CLI examples consistent with `seamcarve-cli --help`, `Sources/SeamCarvingCLI`, and the existing README.
- Explain that Metal is optional and that automatic backend selection can fall back to Accelerate or CPU.
- Do not claim physical-device UI automation is passing; record the known XCTest automation-mode limitation accurately.
- Do not add a documentation build dependency; GitHub Pages must serve the committed static files directly.
- Preserve existing capability and acceptance documents; improve links and navigation rather than duplicating their authoritative matrices.

### Task 1: Audit the public surface and create the documentation information architecture

**Files:**
- Inspect: `Package.swift`
- Inspect: `Sources/SeamCarvingCore/**`, `Sources/SeamCarvingApple/**`, `Sources/SeamCarvingAccelerate/**`, `Sources/SeamCarvingMetal/**`, `Sources/SeamCarvingVision/**`
- Inspect: `Sources/SeamCarvingCLI/**`, `Sources/seamcarve-cli/**`
- Inspect: `Apps/SeamCarvingApp/README.md`, `Apps/SeamCarvingApp/Tests/AcceptanceMatrix.md`, `docs/capability-matrix.md`, `docs/architecture.md`
- Create: `docs/index.html`
- Create: `docs/assets/styles.css`

**Interfaces:**
- The static site navigation must link to `architecture.html`, `principles.html`, `api.html`, `cli.html`, `app.html`, and the existing capability matrix.
- Each page must work when opened directly from a local filesystem and when served from a GitHub Pages project path; use relative links only.

- [ ] **Step 1: Inventory the public modules, products, executable names, and app targets.** Record exact names and supported platforms in the site navigation and README outline.
- [ ] **Step 2: Create the static site shell.** Add a semantic header, navigation, main content container, footer, skip link, responsive layout, code block styling, table styling, and dark-mode CSS using `prefers-color-scheme`.
- [ ] **Step 3: Add a no-JavaScript navigation fallback.** Keep all navigation usable as ordinary relative links; JavaScript may only enhance the active-page marker or mobile menu.
- [ ] **Step 4: Open `docs/index.html` through a local HTTP server and verify every navigation link resolves to an existing file.**
- [ ] **Step 5: Commit the site shell independently.**

```bash
git add docs/index.html docs/assets/styles.css
git commit -m "docs: add static documentation site shell"
```

### Task 2: Write the architecture and algorithm principles guides

**Files:**
- Create: `docs/architecture.html`
- Create: `docs/principles.html`
- Modify: `docs/index.html`
- Modify: `README.md`

**Interfaces:**
- Architecture page must describe the dependency flow `Core -> Accelerate/Metal -> Apple -> Vision`, plus CLI and App consumers.
- Principles page must use the repository’s names: backward Sobel, forward luma, dimension order, protect/remove masks, object removal restoration, face protection, enlargement, and Metal fallback policy.

- [ ] **Step 1: Document the module responsibilities and data flow from platform image input to canonical RGBA8 image, resize engine, and platform output.**
- [ ] **Step 2: Document the seam-carving loop with a concise numbered explanation: energy, dynamic programming, seam selection, mask constraints, edit, progress/cancellation.**
- [ ] **Step 3: Explain horizontal processing, enlargement, Lanczos residual mode, face protection cadences, and the exact limitations of the Metal backend.**
- [ ] **Step 4: Add diagrams using accessible HTML/CSS or inline SVG only; do not add binary diagram dependencies.**
- [ ] **Step 5: Add links from README and index page; verify all technical claims against source and capability matrix.**
- [ ] **Step 6: Commit.**

```bash
git add README.md docs/index.html docs/architecture.html docs/principles.html
git commit -m "docs: explain architecture and seam carving principles"
```

### Task 3: Write the Swift API reference and usage guide

**Files:**
- Create: `docs/api.html`
- Modify: `docs/index.html`
- Modify: `README.md`

**Interfaces:**
- API examples must compile conceptually against the current public symbols: `RGBA8Image`, `PixelSize`, `SeamCarver`, `ResizeOptions`, `AppleSeamCarver`, `AppleSeamCarver.Configuration`, mask types, backend preferences, progress, and cancellation.
- Every example must identify whether it is Core-only, Apple-platform-only, or Vision-enabled.

- [ ] **Step 1: Add a package setup example with `swift package init`/dependency usage and the current platform floors.**
- [ ] **Step 2: Add a minimal Core resize example using canonical RGBA8 data.**
- [ ] **Step 3: Add an Apple facade example for `CGImage`/platform image conversion and backend configuration.**
- [ ] **Step 4: Add mask, progress, cancellation, enlargement, and face-protection examples using the actual public API names.**
- [ ] **Step 5: Add an API limitations section covering Core’s platform independence, Vision optionality, Metal selection, and exact versus approximate pre-scaling.**
- [ ] **Step 6: Check code identifiers with `swift symbolgraph-extract` or source search and commit.**

```bash
git add README.md docs/index.html docs/api.html
git commit -m "docs: add Swift API guide"
```

### Task 4: Write the CLI user guide

**Files:**
- Create: `docs/cli.html`
- Modify: `docs/index.html`
- Modify: `README.md`

**Interfaces:**
- Use the current executable name `seamcarve-cli` and the actual `swift-argument-parser` options.
- Cover single-file and batch modes without inventing flags.

- [ ] **Step 1: Extract the current help text and option definitions from `CLIArgumentParser.swift`, `CLIOptions.swift`, and `SeamCarveCommand.swift`.**
- [ ] **Step 2: Document installation/build commands for local development and show `swift run seamcarve-cli --help`.**
- [ ] **Step 3: Add examples for exact dimensions, percentage, square mode, backend/energy/order, deterministic mode, masks, face protection, output formats, stdin/stdout, remote URLs, and debug artifacts.**
- [ ] **Step 4: Add batch examples for `--input-dir`, `--output-dir`, `--recursive`, and `--concurrency`, including output-path behavior and failure handling.**
- [ ] **Step 5: Add an exit-code/error troubleshooting table based on the existing CLI tests.**
- [ ] **Step 6: Verify every command with `swift run seamcarve-cli --help` and commit.**

```bash
git add README.md docs/index.html docs/cli.html
git commit -m "docs: add CLI user guide"
```

### Task 5: Write the app user guide and platform notes

**Files:**
- Create: `docs/app.html`
- Modify: `docs/index.html`
- Modify: `Apps/SeamCarvingApp/README.md`
- Modify: `README.md`

**Interfaces:**
- Describe one SwiftUI application target for iPhone, iPad, and Mac Catalyst.
- Use the actual UI concepts and labels: import, target width/height, aspect lock, algorithm, dimension order, backend, deterministic, mask toolbar, face protection, export format, Resize, and Export image.

- [ ] **Step 1: Document build/run prerequisites and the current Xcode project generation flow.**
- [ ] **Step 2: Write the normal workflow from image import through configuration, mask painting, face protection, resize/cancel, and PNG/JPEG export.**
- [ ] **Step 3: Add platform-specific layout notes for iPhone, iPad, and Catalyst, including dark-mode controls and Catalyst signing requirements.**
- [ ] **Step 4: Add a testing section distinguishing simulator UI tests, Catalyst unit tests, physical iPad unit tests, physical Metal validation, and the known physical UI automation timeout.**
- [ ] **Step 5: Add troubleshooting for permissions, signing, provisioning profiles, generated Xcode projects, and harmless macOS/Xcode service logs.**
- [ ] **Step 6: Verify UI labels against `ContentView.swift` and commit.**

```bash
git add README.md Apps/SeamCarvingApp/README.md docs/index.html docs/app.html
git commit -m "docs: add cross-platform app guide"
```

### Task 6: Final documentation QA and GitHub Pages validation

**Files:**
- Modify: `README.md`
- Modify: `docs/index.html`
- Modify: `docs/assets/styles.css`
- Inspect: all `docs/*.html`, existing `docs/*.md`

**Interfaces:**
- README must provide a newcomer path: What it is -> install/build -> choose API/CLI/App -> architecture/principles -> tests/limitations.
- Static HTML must contain no absolute repository-local paths and no broken relative links.

- [ ] **Step 1: Check Markdown and HTML links with a local script that resolves every relative `href` and reports missing targets.**
- [ ] **Step 2: Run `git diff --check` and scan for stale claims, `TODO`, `TBD`, placeholder text, and undocumented flags.**
- [ ] **Step 3: Build the package and run the relevant CLI help command after documentation changes.**
- [ ] **Step 4: Serve `docs/` locally and inspect desktop/mobile layout, code blocks, tables, dark mode, keyboard focus, and navigation.**
- [ ] **Step 5: Confirm the GitHub Pages setup instruction is explicit: repository Settings -> Pages -> Deploy from branch -> `/docs`.**
- [ ] **Step 6: Commit the final QA changes.**

```bash
git add README.md docs Apps/SeamCarvingApp/README.md
git commit -m "docs: complete project onboarding documentation"
```

## Verification Checklist

- [ ] A new user can find the correct entry point within one minute.
- [ ] README links to every guide and clearly separates Core, Apple facade, CLI, and App usage.
- [ ] Every CLI option documented is present in the current parser.
- [ ] API examples use current symbols and platform availability.
- [ ] Architecture and algorithm claims match source behavior and capability matrix.
- [ ] GitHub Pages can serve `docs/index.html` without a build step.
- [ ] All static links resolve locally.
- [ ] `git diff --check` passes.
- [ ] Existing tests remain unaffected.
