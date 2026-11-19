# Changelog

Windows용 `HackingToolkit9DS` 배치 스크립트를 macOS/Linux Bash 환경으로 이식한 초기 버전부터 현재의 `3ds-cia-tool.sh`까지의 주요 변경 이력입니다.

---

## [v29] - 한국어/English 다국어 지원 및 최초 실행 언어 선택
- **최초 실행 언어 선택 (`select_initial_language`)**: 설정 파일(`.paths.conf`)에 언어 설정이 없는 최초 실행 시 `한국어 / English` 선택 프롬프트를 표시하고 선택 결과를 영구 저장
- **전 메뉴·메시지 영문화**: macOS 기본 Bash 3.2 호환 다국어 출력 헬퍼(`msg`, `say`, `msgf`)를 도입해 분해, 재구성, 일괄 변환, 헤더 조회, 정리, 설정, 오류 및 안전 경고 메시지 전체 영문 지원
- **언어 전환 경로 확장**: 설정 메뉴(`6. 설정 (경로 / 언어 변경)`) 내 즉시 전환 옵션, CLI 플래그(`-l` / `--lang <ko|en>`), 환경변수(`CIA_LANG`) 지원 추가

## [v28] - 복호화 키 파일(`ext_kry.txt` / `ext_key.txt`) 검증 및 연동
- **키 파일 상태 감지 보강 (`detect_key_files`)**: 스크립트 루트 경로에서 `ext_kry.txt` 및 `ext_key.txt` 존재 여부를 추가로 검사하고, 두 파일이 모두 없을 경우 메인 화면 `Keys:` 항목에 `(주의: ext_kry.txt 없음)` 경고를 표시하도록 개선
- **작업 공간 심볼릭 링크 반영 (`cia_unix_convert`)**: `cia-unix` 실행 시 격리된 `Work/` 폴더 내부로 `ext_kry.txt`와 `ext_key.txt` 심볼릭 링크를 자동 연결하도록 추가

## [v27] - macOS 한글 입력 안정화 및 폴더 삭제 보호 강화
- **한글 프롬프트 커서 깨짐 수정 (`read_line_edit`)**: macOS 기본 Bash 3.2(`libedit`) 환경에서 멀티바이트 한글 프롬프트 출력 후 입력을 받을 때 커서 위치가 어긋나는 문제를 해결하기 위해 `printf` 분리 입력 헬퍼 도입
- **안전 삭제 검증 강화 (`validate_safe_dir`, `clean_extracted`)**:
  - `Desktop`, `Documents`, `Downloads`, `Pictures`, `Movies`, `Music`, `Public` 등 주요 사용자 폴더를 삭제 보호 대상에 추가
  - 기존 CIA 분해 흔적(`.source_name`, `HeaderNCCH0.bin`, `ExeFS`, `RomFS`)이 없는 일반 폴더를 비우려고 할 때 이중 경고 확인 프롬프트 추가
- **공백·괄호 파일명 대응**: `cia-unix` 실행 시 원본 파일명 대신 `Work/input.cia` 고정 심볼릭 링크를 사용해 특수문자·공백으로 인한 내부 파싱 오류 방지
- **재구성 및 시그널 안정성 개선**:
  - 재구성 시 `minor`, `micro` 외에 `major` 버전까지 직접 지정할 수 있도록 확장
  - ExeFS 빌드 중 임시로 이름을 바꾼 `banner.bnr`/`icon.icn`이 `Ctrl+C`(`SIGINT`) 또는 `SIGTERM` 중단 시에도 원래 이름(`.bin`)으로 복원되도록 `trap` 처리 추가
  - 분해·재구성 메뉴에서 입력한 사용자 지정 `EXTRACTED_DIR`이 영구 설정을 덮어쓰지 않고 해당 작업 세션에만 적용되도록 수정

## [v26] - ROM 메타데이터 자동 연동, 일괄 변환 및 헤더 조회 추가
- **메타데이터 파싱 및 자동 연동 (`read_rom_meta`)**: `ctrtool` 출력을 분석해 Title ID, 제품코드, 버전(`major.minor.micro`), 암호화 상태를 추출하고 `.source_meta`에 저장하여 재구성 시 원본 버전 값을 기본값으로 자동 반영
- **CIA → 3DS 일괄 변환 (`batch_convert_input`)**: `Input/` 폴더에 `.cia` 파일이 2개 이상 있을 때 전체 일괄 변환 모드(기존 파일 건너뛰기/모두 덮어쓰기 선택) 지원
- **헤더 정보 조회 메뉴 추가 (`menu_inspect`)**: CIA/3DS/CCI 파일의 용량, Title ID, 제품코드, 버전, 암호화 상태 및 `ctrtool` 상세 출력을 확인하는 메뉴 신설
- **편의성 개선**:
  - Finder 드래그 앤 드롭 시 삽입되는 백슬래시 이스케이프 해제(`unescape_path`) 추가
  - 작업 완료 후 macOS Finder(`open`) 또는 Linux(`xdg-open`)로 결과 폴더를 바로 열 수 있는 `pause_with_open` 도입
  - 메인 화면에 복호화 키 파일 인식 상태(`detect_key_files`) 표시

## [v25] - 유동 작업 경로 설정 및 CLI/환경변수 지원
- **경로 설정 메뉴 및 영구 저장 (`menu_paths`)**: `Input`, `Extracted`, `Output` 기본 경로를 대화형으로 변경하고 `.paths.conf`에 영구 저장·로드(`save_config`, `load_config`)하는 기능 추가
- **CLI 옵션 및 환경변수 지원**: `-i`/`--input`, `-e`/`--extracted`, `-o`/`--output`, `-h`/`--help` 인자 파싱과 `CIA_INPUT_DIR`, `CIA_EXTRACTED_DIR`, `CIA_OUTPUT_DIR` 환경변수 오버라이드 지원
- **기본 안전 경로 검증 (`validate_safe_dir`)**: 루트(`/`), 홈(`$HOME`), 스크립트 루트(`$SCRIPT_DIR`), 주요 시스템 디렉토리가 `rm -rf` 대상이 되지 않도록 차단

## [v24] - 경로 정규화, 로그 정리 및 macOS 파일시스템 호환성 보강
- **입력 경로 정규화 (`normalize_path`)**: 터미널 드래그 앤 드롭 시 붙는 앞뒤 공백, 작은따옴표/큰따옴표 제거 및 `~` 홈 경로 확장 통합 처리
- **외부 도구 로그 래퍼 (`run_tool`)**: 도구 실행 성공 시 불필요한 콘솔 출력을 숨기고, 실패 시에만 임시 로그 파일 내용을 `[상세]` 접두사와 함께 출력하도록 개선
- **macOS 호환성 및 파일 선택 흐름 개선**:
  - macOS 기본 Bash 3.2 호환을 위해 `${var,,}` 대신 `shopt -s nocasematch` 기반 확장자 제거 적용
  - 대소문자 비구분 파일시스템(APFS/HFS+/WSL)에서 `*.cia`와 `*.CIA`가 중복 나열되지 않도록 `find -L ... -iname | sort`로 통합
  - 대상 파일이 0개면 즉시 직접 경로 입력으로 전환하고, 1개만 발견되면 확인 후 바로 선택할 수 있도록 UX 단축

## [v23] - 출력 경로 유연화 및 덮어쓰기 확인 도입
- **직접 경로 입력 옵션 (`pick_file`)**: 파일 선택 목록에서 `p`를 입력해 임의의 외부 경로에 있는 파일을 직접 지정할 수 있도록 추가
- **출력 경로 해석 (`resolve_out_path`)**: 파일명만 입력 시 기본 출력 폴더에 저장하고, 하위 폴더 경로(`sub/name`)나 절대(`/...`)/홈(`~/...`) 경로 입력 시 해당 위치에 자동 디렉토리 생성 후 저장
- **덮어쓰기 방지 (`confirm_overwrite`)**: 출력 대상 경로에 동일 이름의 파일이 이미 존재할 경우 덮어쓰기 여부(`y/N`) 확인 추가

## [v22] - 파이프라인 오류 감지 및 대화형 메뉴 복귀 구조 확립
- **오류 처리 체계 전환**: `set -o pipefail`을 적용해 `makerom ... | tee` 파이프라인 실패를 정확히 감지하고, 작업 실패 시 스크립트가 즉시 종료(`die`)되지 않고 경고(`warn`) 후 메인 메뉴로 복귀하도록 개선
- **크로스 플랫폼 `script` 실행 및 입력 검증**:
  - GNU `script`(`-c`, `-e`)와 BSD/macOS `script` 옵션을 자동 판별해 `cia-unix` PTY 실행 호환성 확보
  - `Work/` 삭제 전 경로 안전 검증 추가, 출력 파일명의 슬래시(`/`) 치환 및 `minor`/`micro` 버전 정수 입력 검증 추가

## [v21] - 4개 전용 폴더 구조 및 `Work/` 격리 공간 도입
- **디렉토리 아키텍처 개편**: 스크립트 루트에 작업 파일이 혼재되던 방식을 `Input/`, `Extracted/`, `Output/`, `Work/` 4개 폴더 체계로 분리
- **격리 실행 및 디버깅 보존**: `cia-unix` 및 빌드 중간 산출물을 `Work/` 내부에서 처리하고, 실패 시 원인 분석을 위해 `Work/` 폴더와 로그를 보존하도록 구성
- **상태 추적 및 파일 선택 UI**: 분해 시 `.source_name`에 원본 파일명을 기록해 재구성 기본 출력명으로 연동하고, 번호 기반 파일 선택기(`pick_file`)와 ExeFS `banner.bin`/`icon.bin` 임시 확장자(`.bnr`/`.icn`) 복원 루틴 도입

## [v10] - `cia-unix` 복호화·변환 엔진 도입 및 전체 파티션 추출
- **변환 백엔드 전환**: 암호화된 CIA 복호화 및 `.3ds` 변환 기본 백엔드를 `cia-unix`로 전환하고, 부재 시 기존 `ctrdecrypt`/`makerom` 방식으로 폴백하도록 구성
- **파티션 추출·재구성 확장 (`extract_from_3ds`)**: `3dstool -xvt01267f cci`로 전체 파티션을 추출해 `ExeFS`/`RomFS`와 함께 `Manual`(NCCH1), `DownloadPlay`(NCCH2) 파티션의 선택적 분해·재구성 지원 및 `banner.bnr`/`icon.icn`의 `.bin` 정규화 적용

## [v9] - `.cci` NoCrypto 플래그 자동 바이너리 패치
- **NCSD/NCCH 헤더 패치 (`patch_cci_nocrypto_flags`)**: 바이너리 오프셋 읽기 헬퍼(`read_u32le`, `read_u8`)를 추가해 `makerom -ciatocci`로 생성된 `.cci` 파일의 NCSD 파티션 테이블을 순회하며 각 NCCH 헤더(`+0x18F`)에 NoCrypto 비트(`0x04`)를 자동 패치하여 Azahar/Citra 에뮬레이터의 암호화 경고 해소

## [v8] - `set -u` 엄격 모드 빈 배열 참조 안전화
- **언바운드 변수 오류 수정**: `set -u` 활성 상태에서 파일이 없을 때 빈 배열(`sorted` 등) 확장으로 스크립트가 비정상 종료되는 문제를 방지하기 위해 배열 길이 사전 검사(`"${#sorted[@]}" -gt 0`) 추가

## [v1 ~ v7] - `3ds-cia-tool.sh` 독립 및 핵심 파이프라인 고도화
- **도구 재편 (`v1`)**: 스크립트명을 `3ds-cia-tool.sh`로 변경하고, 불필요한 Windows 레거시 메뉴를 제거해 CIA/3DS 분해·재구성·변환 핵심 워크플로우 중심으로 재구성
- **추출·빌드 호환성 보강 (`v2` ~ `v3`)**: `3dstool` 및 `ctrtool` 옵션 호환성 수정, `HeaderNCCH0.bin`·`DecryptedExHeader.bin` 및 ExeFS/RomFS 추출·빌드 경로 오류 수정
- **복호화 및 폴백 처리 (`v4` ~ `v5`)**: `ctrdecrypt` 및 `makerom -ciatocci` 변환 기능 통합, `LogoLZ.bin`/`PlainRGN.bin` 누락 시 빈 파일 폴백 빌드 지원
- **탐색 및 정리 개선 (`v6` ~ `v7`)**: 대상 ROM 파일 목록 정렬 및 입력 검증 강화, 작업 중 생성되는 중간 바이너리 파일 정리 루틴 보강

## [Initial Port] - `HackingToolkit9DS.sh` (Windows 배치 스크립트 최초 이식)
- **Bash 포팅**: Windows용 `HackingToolkit9DS.bat`의 대화형 메뉴와 `3dstool`, `ctrtool`, `makerom` 호출 명령을 macOS/Linux Bash 환경에 맞게 최초 이식하여 기본적인 CIA/3DS 추출 및 재구성 파이프라인 구현