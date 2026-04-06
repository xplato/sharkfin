# Sharkfin

Native macOS app for semantic search of local files. Currently only supports images (JPG, PNG, HEIC, WEBP, SVG, etc.).

## Demo

Performing several example searches on my local index of >18,000 files (source size: ~50 GB, database size: ~100 MB).

https://github.com/user-attachments/assets/41a714ae-ced7-45fc-89bf-d6e46dbc8f1c

Note: The UI is very likely to have changed since this demo video was recorded.

## Features and Notes

- **Local-only:** indexing, searching, and all other app functionality apart from the initial CLIP model download is **entirely local.**
- **Natural language searching:** Search indexed files with natural language. Currently, only images are supported.
- **High performance:** Indexing and searching are both highly optimized to leverage the built-in neural engine in macOS. See the screenshots and videos section below for a demo. 

## Implementation

TODO.

## Demos

### Indexing

Performing indexing on two test directories containing several hundred images total. The average filesize for the images in testdir is 3.88 MB and 5.49 MB for testdir2 (i.e. rather large image files).

https://github.com/user-attachments/assets/b502dd63-7f29-4257-bbe7-11e8697a72c6

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
