# Sharkfin

Native macOS app for semantic search of local files. Currently only supports images (JPG, PNG, HEIC, WEBP, SVG, etc.).

## Demo

Performing several example searches on my local index of ~18,000 files (source size: ~50 GB, database size: ~100 MB). This was taken with a search debounce of 150ms, which has since been dropped to 50ms. Either way, it's surprisingly fast.

![Demo GIF](assets/demo.gif)

Note: The UI is very likely to have changed since this demo video was recorded.

## Developing

### Prerequisites

- **macOS 15.4+** (deployment target)
- **Xcode 26.4+** with Swift 5 toolchain

### Getting Started

1. Clone the repository:

```bash
git clone https://github.com/xplato/sharkfin.git
cd sharkfin
```

2. Open the project in Xcode:

```bash
open sharkfin.xcodeproj
```

3. Swift Package Manager dependencies will resolve automatically on first open. The project uses the following packages:
   - [GRDB.swift](https://github.com/groue/GRDB.swift) — SQLite database
   - [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — Global keyboard shortcut handling
   - [onnxruntime-swift-package-manager](https://github.com/microsoft/onnxruntime-swift-package-manager) — ONNX Runtime for CLIP model inference
   - [swift-transformers](https://github.com/huggingface/swift-transformers) — Tokenizer support for CLIP text encoding

4. Select the `sharkfin` scheme and build (`Cmd+B`) or run (`Cmd+R`).

### Architecture

Sharkfin is a menu bar app that provides a global search panel (similar to Spotlight) for semantic image search using CLIP embeddings.

- **CLIP/** — CLIP model management, text/image encoding, and image preprocessing. Models are downloaded from Hugging Face on first launch.
- **Database/** — SQLite persistence via GRDB for indexed files, embeddings, directories, and index jobs.
- **Indexing/** — File scanning, thumbnail generation, and the indexing service that coordinates embedding generation.
- **Search/** — Search UI (panel, bar, results grid, detail view) and the search service/view model.
- **Settings/** — Settings views for directories, keyboard shortcuts, model management, and general preferences.
