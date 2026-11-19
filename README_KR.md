# 3DS CIA Tool (`3ds-cia-tool.sh`)

> **[English](README.md)** | **한국어 (Korean)**

macOS 및 Linux 터미널 환경에서 Nintendo 3DS의 `.cia` 파일을 **분해(Extract), 재구성(Rebuild), `.3ds` 변환(Convert), 헤더 정보 조회(Inspect)**할 수 있는 대화형 Bash 유틸리티입니다.

Windows용 `HackingToolkit9DS`의 워크플로우에서 영감을 받아 macOS(기본 Bash 3.2 포함) 및 Linux 환경에 맞게 새롭게 작성되었습니다.

---

## 주요 기능

- **한국어 / English 다국어 지원**: 최초 실행 시 언어를 선택해 영구 저장하며, 설정 메뉴나 CLI 옵션으로 언제든 전환할 수 있습니다.
- **CIA 분해 (`CIA → Extracted`)**: `cia-unix` 및 `3dstool`을 이용해 암호화/복호화된 CIA에서 `ExeFS`, `RomFS`, `Manual`(NCCH1), `DownloadPlay`(NCCH2) 파티션 및 헤더를 추출합니다.
- **CIA 재구성 (`Extracted → CIA`)**: 수정된 `ExeFS`/`RomFS`를 다시 패키징하며, 분해 시 기록된 원본 메타데이터(`.source_meta`)를 불러와 `major.minor.micro` 버전 기본값을 자동으로 연동합니다.
- **CIA → 3DS 단일 / 일괄 변환**: Azahar/Citra 등 에뮬레이터에서 바로 실행할 수 있는 `.3ds` 포맷 변환 및 `Input/` 폴더 내 다수 파일 일괄 변환(건너뛰기/덮어쓰기 선택)을 지원합니다.
- **헤더 및 메타데이터 조회**: `ctrtool` 출력을 파싱하여 Title ID, 제품코드, 버전, 암호화 여부 요약 및 상세 헤더 정보를 제공합니다.
- **유연한 경로 관리 및 안전 보호**:
  - 대화형 설정 메뉴(`Input`, `Extracted`, `Output` 경로 및 언어 영구 저장), CLI 옵션, 환경변수 지원
  - macOS Finder 드래그 앤 드롭 경로(따옴표·백슬래시 이스케이프·`~`) 자동 정규화
  - 시스템 루트(`/`), 홈 디렉토리, 주요 사용자 폴더(`Desktop`, `Documents`, `Downloads` 등) 및 분해 흔적이 없는 일반 폴더의 오삭제 차단

---

## 사전 준비 (필수 외부 도구)

이 레포지토리에는 외부 바이너리와 복호화 키 파일이 포함되어 있지 않습니다. 스크립트와 **같은 디렉토리**에 아래 실행 도구들을 준비하고 실행 권한(`chmod +x`)을 부여해 주세요.

| 도구명 | 역할 | 공식 배포처 |
| :--- | :--- | :--- |
| **`3dstool`** | CCI / CXI / ExeFS / RomFS 분해 및 빌드 | [dnasdw/3dstool](https://github.com/dnasdw/3dstool/releases) |
| **`ctrtool`** | CIA / 3DS 헤더 및 메타데이터 파싱 | [3DSGuy/Project_CTR](https://github.com/3DSGuy/Project_CTR/releases) |
| **`makerom`** | 빌드된 파티션을 `.cia` 파일로 패키징 | [3DSGuy/Project_CTR](https://github.com/3DSGuy/Project_CTR/releases) |
| **`cia-unix`** | 암호화된 CIA 복호화 및 `.3ds` 변환 | 사용 중인 `cia-unix` 릴리스 빌드 |

### 복호화 키 파일 (암호화된 CIA 처리 시)
암호화된 타이틀을 복호화하려면 `cia-unix`가 참조할 수 있도록 스크립트와 같은 폴더에 아래 키 파일을 배치해야 합니다. (메인 화면의 `Keys:` 항목에서 인식 여부를 확인할 수 있습니다.)
- `ext_key.txt`
- 필요에 따라 `seeddb.bin`, `boot9.bin`, `aes_keys.txt`, `encseed.bin` 등

---

## 폴더 구조

스크립트를 처음 실행하면 기본 작업 폴더가 자동으로 생성됩니다.

```text
3ds-cia-tool/
├── 3ds-cia-tool.sh      # 메인 스크립트 (macOS에서는 .command 확장자로 더블클릭 실행 가능)
├── 3dstool              # [사용자 준비] 외부 바이너리
├── ctrtool              # [사용자 준비] 외부 바이너리
├── makerom              # [사용자 준비] 외부 바이너리
├── cia-unix             # [사용자 준비] 외부 바이너리
├── ext_key.txt          # [사용자 준비] 복호화 키 파일
├── Input/               # 원본 .cia 파일을 넣는 기본 입력 폴더
├── Extracted/           # 분해된 헤더, ExeFS, RomFS 등이 저장되는 작업 폴더
├── Output/              # 재구성된 .cia 또는 변환된 .3ds 결과물 출력 폴더
├── Work/                # 실행 중 임시 파일을 처리하는 격리 공간 (완료 시 자동 삭제)
└── .paths.conf          # 메뉴 6번에서 변경한 기본 경로 및 언어 설정 저장 파일
```

---

## 설치 및 실행 방법

1. **레포지토리 클론 및 외부 도구 배치**
   ```bash
   git clone [https://github.com/](https://github.com/)<your-username>/<your-repo-name>.git
   cd <your-repo-name>
   ```
   위에서 준비한 `3dstool`, `ctrtool`, `makerom`, `cia-unix` 바이너리와 키 파일(`ext_key.txt`)을 이 폴더에 넣습니다.

2. **실행 권한 부여**
   ```bash
   chmod +x 3ds-cia-tool.sh 3dstool ctrtool makerom cia-unix
   ```
   *(macOS에서 Finder 더블클릭으로 실행하려면 `3ds-cia-tool.sh`의 이름을 `3dsCiaTool.command`로 변경하면 편리합니다.)*

3. **실행**
   ```bash
   ./3ds-cia-tool.sh
   ```
   최초 실행 시 **한국어** 또는 **English**를 선택하는 화면이 표시됩니다.

---

## CLI 옵션 및 환경변수

기본 폴더(`Input`, `Extracted`, `Output`) 및 표시 언어를 지정해 실행할 수 있습니다.

### CLI 옵션
```bash
./3ds-cia-tool.sh [옵션]

옵션:
  -i, --input <경로>      기본 입력(CIA) 폴더 지정
  -e, --extracted <경로>  분해(Extracted) 작업 폴더 지정
  -o, --output <경로>     기본 출력(CIA/3DS) 폴더 지정
  -l, --lang <ko|en>      표시 언어 지정 (ko 또는 en)
  -h, --help              도움말 표시
```

### 환경변수
`CIA_INPUT_DIR`, `CIA_EXTRACTED_DIR`, `CIA_OUTPUT_DIR`, `CIA_LANG` 환경변수를 설정해 기본값을 덮어쓸 수 있습니다.  
*(우선순위: `CLI 옵션` > `환경변수` > `.paths.conf` 설정값)*

---

## 메뉴 구성

1. **CIA 분해 (`CIA → Extracted`)**: `Input/` 또는 지정 경로의 `.cia` 파일을 선택해 파티션과 리소스를 추출합니다.
2. **CIA 재구성 (`Extracted → CIA`)**: 수정이 끝난 `Extracted/` 폴더 내용을 새로운 `.cia` 파일로 빌드합니다.
3. **CIA → 3DS 변환 (단일 / 일괄 변환)**: `.cia` 파일을 에뮬레이터용 `.3ds` 파일로 변환합니다.
4. **CIA / 3DS 헤더 정보 조회**: Title ID, 제품코드, 버전, 암호화 상태 및 `ctrtool` 상세 정보를 확인합니다.
5. **작업 파일 정리**: `Extracted/`, `Work/` 및 잔여 복호화 임시 파일을 안전하게 정리합니다.
6. **설정 (경로 / 언어 변경)**: `Input`, `Extracted`, `Output` 기본 경로 및 표시 언어(한국어/English)를 변경하고 `.paths.conf`에 영구 저장합니다.
7. **종료**: 프로그램을 종료합니다.

---

## 면책 조항 및 출처 (Disclaimer & Credits)

- **면책 조항**: 본 도구는 본인이 합법적으로 소유한 게임 백업 및 홈브류 연구·로컬라이징 목적으로만 사용해야 합니다. 저작권이 있는 ROM이나 암호화 키 파일의 무단 공유 및 배포를 지원하지 않습니다.
- **Credits**:
  - Initially inspired by and ported from [HackingToolkit9DS](https://github.com/Asia81/HackingToolkit9DS) by Asia81.
  - Powered by external CLI tools: `3dstool` (dnasdw), `ctrtool` & `makerom` (3DSGuy), and `cia-unix`.
  - **AI Assistance**: **Gemini** 및 **DeepSeek**의 도움을 받아 개발·리팩토링 및 문서화되었습니다.
- **License**: [MIT License](LICENSE)에 따라 배포됩니다.