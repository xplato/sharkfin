<div align="center">

<div id="user-content-toc">
  <ul align="center" style="list-style: none;">
    <summary>
      <h1>Sharkfin</h1>
    </summary>
  </ul>
</div>

**A better way to find files on Mac**

<img width="1920" height="1080" alt="Sharkfin Header" src="https://github.com/user-attachments/assets/b9e6999b-7992-40dc-9dc9-b41d48051510" />

### 

Sharkfin is a native macOS app for semantic search of local files. Currently only supports images (JPG, PNG, HEIC, WEBP, SVG, etc.).

</div>

## Features

- **Local-only:** indexing, searching, and all other app functionality apart from the initial CLIP model download is **entirely local.**
- **Natural language searching:** Search indexed files with natural language. Currently, only images are supported.
- **High performance:** Indexing and searching are both highly optimized to leverage the built-in neural engine in macOS. See the screenshots and videos section below for a demo. 

## Demos

### Search

Performing several example searches on my local index of >18,000 files (source size: ~50 GB, database size: ~100 MB).

https://github.com/user-attachments/assets/b9de95a4-aaed-4876-bc39-3c4e3b554462

Note: The UI is very likely to have changed since this demo video was recorded.

#### Other Search Examples

(I have an egregious amount of unique design assets from Creative Market 😅)

<img width="1468" height="1224" alt="CleanShot 2026-04-06 at 17 42 17@2x" src="https://github.com/user-attachments/assets/644dfa59-6846-4697-84e8-555d4bfce58f" />

<img width="1446" height="1218" alt="CleanShot 2026-04-06 at 17 43 02@2x" src="https://github.com/user-attachments/assets/c7598183-02fd-4db8-9247-2e179b97761a" />

<img width="1448" height="1212" alt="CleanShot 2026-04-06 at 17 43 40@2x" src="https://github.com/user-attachments/assets/1b94fea9-bf42-4663-8a08-c29e59c46790" />

### Indexing

Performing indexing on two test directories containing several hundred images total. The average filesize for the images in testdir is 3.88 MB and 5.49 MB for testdir2 (i.e. rather large image files).

https://github.com/user-attachments/assets/b502dd63-7f29-4257-bbe7-11e8697a72c6

## Installation

⚠️ Installing Sharkfin for general usage is currently on pause until Apple approves my developer account (been pending for a bit). In the meantime, you can build the app from source using Xcode by following the instructions in the Developing section below.

## Usage

When you open Sharkfin for the first time, you'll see a welcome screen (pictured below) with instructions on how to get started. The same instructions are repeated here with more detail.

Screenshots below include UI from Sharkfin that may differ from the UI of the current version. Functionality remains the same, unless otherwise noted. 

### 1. Downloading CLIP Models

Sharkfin requires downloading CLIP models from Hugging Face to perform indexing. These are models I've cloned onto my personal HF account.

<img width="1272" height="494" alt="CleanShot 2026-04-06 at 17 33 26@2x" src="https://github.com/user-attachments/assets/a931977e-278c-4416-9717-a786ac09de12" />

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

<img width="1418" height="1386" alt="CleanShot 2026-04-06 at 17 32 09@2x" src="https://github.com/user-attachments/assets/0f0c8a04-27bf-4ba4-a8f2-999736ed1bf0" />

#### Indexing Performance and Functionality

Depending on the number of files and their respective sizes, the initial index of the added directory could take some time, but typically it is very fast. Once added, Sharkfin will listen to file system events and automatically index new, modified, or deleted files (this behavior can be disabled in the "Advanced" tab of Sharkfin's settings).

Performing a new index is typically a lightweight operation, as any files that have already been indexed will be skipped. If you want to completely re-index a previously added directory, you can do so by clicking the trash icon of the directory. This will remove the directory from Sharkfin and delete all existing embeddings and thumbnails. You can then add it back.

<img width="1368" height="932" alt="CleanShot 2026-04-06 at 17 32 51@2x" src="https://github.com/user-attachments/assets/d671d04d-7f74-4e1b-92c8-586185db9a61" />

#### Enabled Directories

The toggle in the directory row controls the enabled or disabled state of the directory. When disabled, Sharkfin will exclude files in that directory from the search results; disabling a directory simply hides results, it doesn't affect the existing indexes and embeddings.

<img width="1240" height="282" alt="CleanShot 2026-04-06 at 17 32 58@2x" src="https://github.com/user-attachments/assets/d6d92901-59da-46fd-845d-a6cb9c87ed98" />

### 3. Search

Once models have been downloaded and directories have been added, you can now search your files using more semantic expressions. By default, Sharkfin is activated with Shift+Command+Space, but this shortcut can be changed in the "Shortcuts" tab in Sharkfin settings.

<img width="1614" height="1364" alt="CleanShot 2026-04-06 at 17 31 33@2x" src="https://github.com/user-attachments/assets/d47ee893-6f1a-4271-a0b0-75353f272ae9" />

### Welcome Screen

<img width="1200" height="1176" alt="CleanShot 2026-04-06 at 17 07 26@2x" src="https://github.com/user-attachments/assets/884bf74f-9515-4343-b93a-6ba25ad642da" />

## Implementation

Sharkfin uses [CLIP](https://openai.com/index/clip/) (Contrastive Language-Image Pre-Training) to embed both images and text into a shared 512-dimensional vector space, enabling natural language search over local image files.

### Indexing

Indexing is triggered either by filesystem events (via `FSEvents`) or manually by the user. The pipeline has three phases:

1. **Scan:** `FileScanner` recursively walks the target directory, collecting metadata (path, size, modification date) for supported image types. No file contents are read at this stage.
2. **Diff:** The indexing service compares scanned files against the database, skipping files that are already indexed and unchanged. Deleted files are removed from the database.
3. **Process (up to 8 concurrent tasks per file):**
   - Load and downscale the image if needed.
   - Compute a SHA-256 content hash.
   - Preprocess the image for CLIP (resize, center-crop to 224x224, normalize with ImageNet stats, arrange in CHW layout).
   - Encode the image into a 512-dimensional, L2-normalized embedding via the CLIP vision model.
   - Generate a content-addressed thumbnail (256px max).
   - Persist the `IndexedFile` and `FileEmbedding` records in a single database transaction.

After indexing completes, the in-memory search cache is invalidated.

### Embedding

CLIP inference is performed locally using two ONNX models (~350 MB vision, ~250 MB text) run via [ONNX Runtime](https://onnxruntime.ai/):

- **Image encoding** uses the CoreML execution provider for hardware acceleration (Neural Engine/GPU). The preprocessed `[1, 3, 224, 224]` tensor is passed through the vision model and the output is L2-normalized.
- **Text encoding** runs on CPU (to avoid CoreML dynamic-shape issues). Input text is tokenized to 77 tokens via `swift-transformers`, passed through the text model, and L2-normalized.

Both encoders produce unit-length vectors in the same latent space, so cosine similarity reduces to a simple dot product.

### Search

When the user types a query:

1. The query text is encoded into a 512-dim vector via the CLIP text encoder.
2. On first search (or after cache invalidation), all stored embeddings are loaded into a contiguous in-memory cache.
3. A single `vDSP_mmul` call (Apple Accelerate) computes the dot product of the query vector against all stored embeddings at once.
4. Results below a similarity threshold (0.16) are discarded, remaining scores are normalized to a 0–1 relevance scale, sorted, and capped at 50.

Similar-image search uses the same approach, substituting a stored image embedding for the text query vector.

### Storage

All data is stored locally in a SQLite database (via [GRDB](https://github.com/groue/GRDB.swift)) with tables for directories, indexed files, embeddings (stored as raw float blobs), and index job status. Thumbnails are stored as JPEG/PNG files on disk, content-addressed by hash to avoid duplicates.

## Search Quality

Generally, I've found the results to be pretty good—sometimes surprisingly so (see the "woman as a flamingo" example above). However, in other cases the results are quite strange. Here's an example:

<img width="1464" height="1226" alt="CleanShot 2026-04-06 at 17 53 34@2x" src="https://github.com/user-attachments/assets/b9caadb5-04f5-4f79-b880-f279d8be0d57" />

It's returning rather abstract vectors. While I don't necessarily have any images of an ostensible airplane plilot, I do have images that are quite close to that, both in terms of implicit meaning and explicit text.

<img width="1420" height="1186" alt="CleanShot 2026-04-06 at 17 56 23@2x" src="https://github.com/user-attachments/assets/97da4b51-57e0-4a0b-b977-470c371eff1b" />

or, more explicitly:

<img width="1640" height="1154" alt="CleanShot 2026-04-06 at 17 54 00@2x" src="https://github.com/user-attachments/assets/6a83b325-7e19-4339-a811-15c44e208e1c" />

Neither of these two images were included in the search results for "pilot."

Improving the quality of search results is, of course, a priority moving forward.

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
