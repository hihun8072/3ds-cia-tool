# 3DS CIA Tool (`3ds-cia-tool.sh`)

> **English** | **[한국어 (Korean)](README_KR.md)**

An interactive Bash utility for **macOS** and **Linux** to **extract, rebuild, batch-convert (`.cia` → `.3ds`), and inspect** Nintendo 3DS `.cia` files from the terminal.

Inspired by the workflow of Windows `HackingToolkit9DS`, rewritten from scratch for Unix-like environments (including macOS default Bash 3.2).

---

## Key Features

- **Bilingual Interface (English / Korean)**: Prompts for language selection on first launch and saves your preference permanently (switchable anytime via Settings or CLI flags).
- **Extract CIA (`CIA → Extracted`)**: Decrypts and unpacks `.cia` files via `cia-unix` and `3dstool` into `ExeFS`, `RomFS`, `Manual` (NCCH1), `DownloadPlay` (NCCH2), and partition headers.
- **Rebuild CIA (`Extracted → CIA`)**: Repackages modified `ExeFS` and `RomFS` directories into a valid `.cia`, automatically reading original metadata (`.source_meta`) to prefill `major.minor.micro` version numbers.
- **Single & Batch CIA → 3DS Conversion**: Converts `.cia` files into `.3ds` format ready for emulators such as Azahar or Citra, with batch conversion support (`skip` or `overwrite all`) when multiple `.cia` files are placed in `Input/`.
- **Header & Metadata Inspector**: Parses Title ID, Product Code, Title Version, and encryption status via `ctrtool`, with an option to view full header details.
- **Flexible Path Management & Safety Guards**:
  - Interactive path & language settings persisted in `.paths.conf`, plus CLI flags and environment variable overrides.
  - Automatic normalization for macOS Finder drag-and-drop paths (quotes, backslash escapes, and `~` expansion).
  - Built-in safeguards preventing accidental deletion of `/`, `$HOME`, major user directories (`Desktop`, `Documents`, `Downloads`, etc.), or non-extraction folders.

---

## Prerequisites

This repository does **not** bundle external binaries or decryption keys. Place the required CLI tools in the **same directory** as `3ds-cia-tool.sh` and grant them execute permissions (`chmod +x`).

| Tool | Purpose | Official Source |
| :--- | :--- | :--- |
| **`3dstool`** | Extract and rebuild CCI / CXI / ExeFS / RomFS | [dnasdw/3dstool](https://github.com/dnasdw/3dstool/releases) |
| **`ctrtool`** | Parse CIA / 3DS headers and metadata | [3DSGuy/Project_CTR](https://github.com/3DSGuy/Project_CTR/releases) |
| **`makerom`** | Package rebuilt partitions into a `.cia` file | [3DSGuy/Project_CTR](https://github.com/3DSGuy/Project_CTR/releases) |
| **`cia-unix`** | Decrypt encrypted `.cia` files and convert to `.3ds` | [shijimasoft/cia-unix](https://github.com/shijimasoft/cia-unix/releases/) |

### Decryption Key Files (For Encrypted CIAs)
To decrypt encrypted titles, place the key files required by `cia-unix` in the script root directory (detection status is displayed under `Keys:` on the main screen):
- `ext_key.txt`
- Optional/additional files as needed: `seeddb.bin`, `boot9.bin`, `aes_keys.txt`, `encseed.bin`

---

## Directory Structure

Default working directories are created automatically on first run:

```text
3ds-cia-tool/
├── 3ds-cia-tool.sh      # Main script (rename to .command on macOS to double-click)
├── 3dstool              # [User-provided] External binary
├── ctrtool              # [User-provided] External binary
├── makerom              # [User-provided] External binary
├── cia-unix             # [User-provided] External binary
├── ext_key.txt          # [User-provided] Decryption key file
├── Input/               # Default input directory for source .cia files
├── Extracted/           # Working directory for extracted headers, ExeFS, and RomFS
├── Output/              # Default output directory for rebuilt .cia / converted .3ds files
├── Work/                # Isolated scratch directory during execution (auto-cleaned on success)
└── .paths.conf          # Saved path and language preferences
```

---

## Installation & Usage

1. **Clone the repository and add external tools**
   ```bash
   git clone [https://github.com/](https://github.com/)<your-username>/<your-repo-name>.git
   cd <your-repo-name>
   ```
   Copy `3dstool`, `ctrtool`, `makerom`, `cia-unix`, and your key file (`ext_key.txt`) into this directory.

2. **Grant execute permissions**
   ```bash
   chmod +x 3ds-cia-tool.sh 3dstool ctrtool makerom cia-unix
   ```
   *(Tip for macOS: Rename `3ds-cia-tool.sh` to `3dsCiaTool.command` if you want to launch it by double-clicking in Finder.)*

3. **Run the script**
   ```bash
   ./3ds-cia-tool.sh
   ```
   On first launch, you will be prompted to select **Korean** or **English**.

---

## CLI Options & Environment Variables

You can override default paths and display language at launch:

### CLI Options
```bash
./3ds-cia-tool.sh [options]

Options:
  -i, --input <path>      Set default input (CIA) folder
  -e, --extracted <path>  Set extraction (Extracted) working folder
  -o, --output <path>     Set default output (CIA/3DS) folder
  -l, --lang <ko|en>      Set display language (ko or en)
  -h, --help              Show this help message
```

### Environment Variables
`CIA_INPUT_DIR`, `CIA_EXTRACTED_DIR`, `CIA_OUTPUT_DIR`, and `CIA_LANG` are also supported.  
*(Precedence: `CLI Options` > `Environment Variables` > `.paths.conf`)*

---

## Menu Overview

1. **Extract CIA (`CIA → Extracted`)**: Select a `.cia` file from `Input/` (or a custom path) and extract its partitions and contents.
2. **Rebuild CIA (`Extracted → CIA`)**: Rebuild the contents of `Extracted/` into a new `.cia` file with customizable version numbers.
3. **Convert CIA → 3DS (Single / Batch)**: Convert a single `.cia` or batch-convert all `.cia` files in `Input/` to `.3ds`.
4. **Inspect CIA / 3DS Header**: View file size, Title ID, Product Code, Version, Encryption status, and detailed `ctrtool` output.
5. **Clean Up Working Files**: Safely remove `Extracted/`, `Work/`, and leftover temporary decrypted files.
6. **Settings (Paths / Language)**: Configure persistent `Input`, `Extracted`, `Output` directories or switch between English and Korean.
7. **Exit**: Quit the tool.

---

## Disclaimer & Credits

- **Disclaimer**: This tool is intended solely for homebrew development, localization, and personal backups of games you legally own. Neither copyrighted ROMs nor decryption keys are provided or condoned.
- **Credits**:
  - Initially inspired by and ported from [HackingToolkit9DS](https://github.com/Asia81/HackingToolkit9DS) by Asia81.
  - Powered by external CLI tools: `3dstool` (dnasdw), `ctrtool` & `makerom` (3DSGuy), and `cia-unix`.
  - **AI Assistance**: Developed, refactored, and documented with assistance from **Gemini** and **DeepSeek**.
- **License**: Distributed under the [MIT License](LICENSE).
