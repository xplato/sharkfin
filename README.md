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

## Installation

Installing Sharkfin for general usage is currently on pause until Apple approves my developer account (been pending for a bit). In the meantime, you can build the app from source using Xcode by following the instructions in the Developing section below.

## Usage

When you open Sharkfin for the first time, you'll see a welcome screen (pictured below) with instructions on how to get started. The same instructions are repeated here with more detail.

Screenshots below include UI from Sharkfin that may differ from the UI of the current version. Functionality remains the same, unless otherwise noted. 

### 1. Downloading CLIP Models

Sharkfin requires downloading CLIP models from Hugging Face to perform indexing. These are models I've cloned onto my personal HF account.

[downloading models image]

Note that the in-app download logic is a bit hacky because HF's Xet CDN is really unreliable. With that said, downloading *does* appear to be working. If you encounter issues downloading the models in-app, you can instead download them from HF manually and put them in Sharkfin's data directory.

<details>

<summary>Manually Downloading CLIP Models</summary>

#### Download the Vision Model

1. Visit https://huggingface.co/xplato/clip-vit-base-patch32-vision-onnx/tree/main
2. Download the following files (each must be downloaded individually 🙄): `config.json`, `model.onnx`, and `preprocessor_config.json`
3. Open Sharkfin's data directory in Finder. You can find this by clicking the "Open in Finder" button in the Storage section of the Advanced tab in Sharkfin's settings, or by visiting this directory: `/Users/<your username>/Library/Application Support/com.lgx.sharkfin`
4. Create the `models` directory if it doesn't exist.
5. Within models, create a new folder: `clip-vit-base-patch32-vision-onnx`
6. Move the files you downloaded from Hugging Face into that directory.

#### Download the Text Model

1. Visit https://huggingface.co/xplato/clip-vit-base-patch32-text-onnx/tree/main
2. Download the following files (each must be downloaded individually 🙄): `config.json`, `merges.txt`, `model.onnx`, `special_tokens_map.json`, `tokenizer_config.json`, `tokenizer.json`, and `vocab.json`
3. Open Sharkfin's data directory in Finder. You can find this by clicking the "Open in Finder" button in the Storage section of the Advanced tab in Sharkfin's settings, or by visiting this directory: `/Users/<your username>/Library/Application Support/com.lgx.sharkfin`
4. Create the `models` directory if it doesn't exist.
5. Within models, create a new folder: `clip-vit-base-patch32-text-onnx`
6. Move the files you downloaded from Hugging Face into that directory.

</details>

### 2. Adding Target Directories

Sharkfin works on directories you add to the app. In the "General" tab of Sharkfin's settings, add relevant directories in the "Directories" section. Once added, indexing will automatically be performed. You can manually re-index the directory at anytime by pressing the refresh icon next to the enable toggle.

[directory list image]

**Indexing Performance and Functionality**

Depending on the number of files and their respective sizes, the initial index of the added directory could take some time, but typically it is very fast. Once added, Sharkfin will listen to file system events and automatically index new, modified, or deleted files (this behavior can be disabled in the "Advanced" tab of Sharkfin's settings).

Performing a new index is typically a lightweight operation, as any files that have already been indexed will be skipped. If you want to completely re-index a previously added directory, you can do so by clicking the trash icon of the directory. This will remove the directory from Sharkfin and delete all existing embeddings and thumbnails. You can then add it back.

[indexing progress image]

**Enabled Directories**

The toggle in the directory row controls the enabled or disabled state of the directory. When disabled, Sharkfin will exclude files in that directory from the search results; disabling a directory simply hides results, it doesn't affect the existing indexes and embeddings.

[enabled toggle image]

### 3. Search

Once models have been downloaded and directories have been added, you can now search your files using more semantic expressions. By default, Sharkfin is activated with Shift+Command+Space, but this shortcut can be changed in the "Shortcuts" tab in Sharkfin settings.

[searchbar image]

### Welcome Screen

[welcome screen image]

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
