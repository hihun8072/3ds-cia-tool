#!/usr/bin/env bash
# 3ds-cia-tool.sh (v29 - 한국어/English 다국어 지원 및 최초 실행 언어 선택)
set -u
set -o pipefail
shopt -s nullglob

ORIG_PWD="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

DEFAULT_INPUT_DIR="$SCRIPT_DIR/Input"
DEFAULT_EXTRACTED_DIR="$SCRIPT_DIR/Extracted"
DEFAULT_OUTPUT_DIR="$SCRIPT_DIR/Output"

INPUT_DIR="$DEFAULT_INPUT_DIR"
EXTRACTED_DIR="$DEFAULT_EXTRACTED_DIR"
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
WORK_DIR="$SCRIPT_DIR/Work"
CONFIG_FILE="$SCRIPT_DIR/.paths.conf"
LANG_CODE=""

THREE="$SCRIPT_DIR/3dstool"
CTR="$SCRIPT_DIR/ctrtool"
MAKEROM="$SCRIPT_DIR/makerom"
CIAUNIX="$SCRIPT_DIR/cia-unix"

# ---------- 다국어 헬퍼 (Bash 3.2 호환) ----------
msg() {
    if [[ "${LANG_CODE:-en}" == "ko" ]]; then
        printf '%s' "$1"
    else
        printf '%s' "$2"
    fi
}

say() {
    if [[ "${LANG_CODE:-en}" == "ko" ]]; then
        printf '%s\n' "$1"
    else
        printf '%s\n' "$2"
    fi
}

msgf() {
    local fmt_ko="$1" fmt_en="$2"
    shift 2
    if [[ "${LANG_CODE:-en}" == "ko" ]]; then
        # shellcheck disable=SC2059
        printf "$fmt_ko" "$@"
    else
        # shellcheck disable=SC2059
        printf "$fmt_en" "$@"
    fi
}

# ---------- 유틸 ----------
die()  { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARNING: $*" >&2; }

pause() {
    local p
    p="$(msg "계속하려면 Enter를 누르세요..." "Press Enter to continue...")"
    echo
    read -rp "$p" _
}

is_yes() { case "${1:-}" in [Yy]*) return 0;; *) return 1;; esac; }
file_size() { stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || echo 0; }

# macOS libedit(Bash 3.2) 멀티바이트 프롬프트 커서 깨짐 방지용 입력 헬퍼
read_line_edit() {
    local prompt="$1" var_name="$2" input=""
    printf '%s' "$prompt" >&2
    if ! IFS= read -er input; then
        return 1
    fi
    printf -v "$var_name" '%s' "$input"
}

open_folder() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        warn "$(msgf "폴더가 존재하지 않습니다: %s" "Folder does not exist: %s" "$dir")"
        return 1
    fi
    if command -v open >/dev/null 2>&1; then
        open "$dir" >/dev/null 2>&1 &
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$dir" >/dev/null 2>&1 &
    else
        msgf "  경로: %s\n" "  Path: %s\n" "$dir"
    fi
}

pause_with_open() {
    local dir="$1"
    local label="${2:-$(msg "폴더 열기" "Open folder")}"
    local ans prompt
    prompt="$(msgf "Enter=계속, o=%s: " "Enter=Continue, o=%s: " "$label")"
    echo
    read -rp "$prompt" ans || return 0
    if [[ "$ans" == "o" || "$ans" == "O" ]]; then
        open_folder "$dir"
    fi
}

# 외부 도구 실행 래퍼 (성공 시 출력 숨김, 실패 시에만 상세 로그 출력)
run_tool() {
    local log_file tag
    tag="$(msg "상세" "Detail")"
    log_file="$(mktemp "${TMPDIR:-/tmp}/3dsciatool.XXXXXX")" || {
        "$@" >/dev/null 2>&1
        return $?
    }
    if ! "$@" >"$log_file" 2>&1; then
        if [[ -s "$log_file" ]]; then
            sed "s/^/    [$tag] /" "$log_file" >&2
        fi
        rm -f -- "$log_file"
        return 1
    fi
    rm -f -- "$log_file"
    return 0
}

# 백슬래시 이스케이프 해제 (macOS Finder 드래그 앤 드롭 대응, UTF-8 안전)
unescape_path() {
    local s="$1" out="" i=0 len=${#1} ch next
    while (( i < len )); do
        ch="${s:i:1}"
        if [[ "$ch" == "\\" && $((i + 1)) -lt len ]]; then
            next="${s:i+1:1}"
            out+="$next"
            ((i += 2))
        else
            out+="$ch"
            ((i += 1))
        fi
    done
    printf '%s' "$out"
}

# 경로 정규화 (앞뒤 공백, 드래그 앤 드롭 따옴표/이스케이프, ~ 확장)
normalize_path() {
    local p="$1"
    p="${p#"${p%%[![:space:]]*}"}"
    while [[ "$p" =~ [[:space:]]$ && ! "$p" =~ \\[[:space:]]$ ]]; do
        p="${p%?}"
    done

    if [[ ${#p} -ge 2 && "$p" == \'*\' ]]; then
        p="${p:1:${#p}-2}"
    elif [[ ${#p} -ge 2 && "$p" == \"*\" ]]; then
        p="${p:1:${#p}-2}"
    else
        p="$(unescape_path "$p")"
    fi

    case "$p" in
        "~")    p="$HOME" ;;
        "~/"*)  p="$HOME/${p#\~/}" ;;
    esac
    printf '%s' "$p"
}

# 디렉토리 경로를 절대 경로로 변환 (존재하지 않는 신규 경로도 처리)
resolve_dir_path() {
    local raw="$1" base_dir="${2:-$SCRIPT_DIR}"
    raw="$(normalize_path "$raw")"
    [[ -z "$raw" ]] && return 1

    [[ "$raw" != /* ]] && raw="$base_dir/$raw"
    while [[ "$raw" != "/" && "$raw" == */ ]]; do
        raw="${raw%/}"
    done

    if [[ -d "$raw" ]]; then
        (cd "$raw" 2>/dev/null && pwd) || printf '%s\n' "$raw"
        return 0
    fi

    local parent="${raw%/*}"
    local name="${raw##*/}"
    [[ -z "$parent" ]] && parent="/"
    if [[ -d "$parent" ]]; then
        local abs_parent
        abs_parent="$(cd "$parent" 2>/dev/null && pwd)" || abs_parent="$parent"
        if [[ "$abs_parent" == "/" ]]; then
            printf '/%s\n' "$name"
        else
            printf '%s/%s\n' "$abs_parent" "$name"
        fi
        return 0
    fi

    printf '%s\n' "$raw"
}

# rm -rf 대상 디렉토리 안전 검증 (루트, 홈, 주요 사용자 폴더, 스크립트 루트 등 보호)
validate_safe_dir() {
    local target="$1"
    local label="${2:-$(msg "대상 경로" "target path")}"
    [[ -n "$target" ]] || die "$(msgf "%s 가 비어 있습니다." "%s is empty." "$label")"

    local check="$target"
    if [[ -d "$target" ]]; then
        check="$(cd "$target" 2>/dev/null && pwd -P)" || check="$target"
    fi
    while [[ "$check" != "/" && "$check" == */ ]]; do
        check="${check%/}"
    done

    local home_clean="${HOME%/}"
    case "$check" in
        "/"|"$home_clean"|"$SCRIPT_DIR"|\
        "$home_clean/Desktop"|"$home_clean/Documents"|"$home_clean/Downloads"|\
        "$home_clean/Pictures"|"$home_clean/Movies"|"$home_clean/Music"|"$home_clean/Public"|\
        "/Users"|"/home"|"/tmp"|"/var"|"/etc"|"/usr"|"/bin"|"/sbin"|"/opt"|"/System"|"/Library"|"/Applications")
            die "$(msgf "안전상의 이유로 삭제/초기화할 수 없는 %s 입니다: %s" "For safety reasons, %s cannot be deleted or reset: %s" "$label" "$check")"
            ;;
    esac

    local stripped="${check#/}"
    [[ "$stripped" == */* ]] || die "$(msgf "최상위 경로는 %s 로 사용할 수 없습니다: %s" "A top-level path cannot be used as %s: %s" "$label" "$check")"
}

# ---------- 설정 저장 / 로드 / 언어 선택 / CLI 인자 ----------
save_config() {
    cat > "$CONFIG_FILE" <<EOF
LANG_CODE=$(printf '%q' "$LANG_CODE")
INPUT_DIR=$(printf '%q' "$INPUT_DIR")
EXTRACTED_DIR=$(printf '%q' "$EXTRACTED_DIR")
OUTPUT_DIR=$(printf '%q' "$OUTPUT_DIR")
EOF
}

load_config() {
    [[ -f "$CONFIG_FILE" ]] || return 0
    # shellcheck disable=SC1090
    source "$CONFIG_FILE" 2>/dev/null || warn "Failed to load config file: $CONFIG_FILE"
}

select_initial_language() {
    local choice
    while true; do
        clear
        echo "=================================================="
        echo " 3DS CIA Tool — Language / 언어 선택"
        echo "=================================================="
        echo
        echo " 1. 한국어 (Korean)"
        echo " 2. English (영어)"
        echo
        read -rp "Select / 선택 [1-2]: " choice || exit 0
        case "$choice" in
            1|ko|KO)
                LANG_CODE="ko"
                save_config
                return
                ;;
            2|en|EN)
                LANG_CODE="en"
                save_config
                return
                ;;
            *)
                echo "Invalid selection. / 잘못된 입력입니다."
                sleep 1
                ;;
        esac
    done
}

print_usage() {
    if [[ "${LANG_CODE:-}" == "ko" ]]; then
        cat <<EOF
사용법: $(basename "$0") [옵션]

옵션:
  -i, --input <경로>      기본 입력(CIA) 폴더 지정
  -e, --extracted <경로>  분해(Extracted) 작업 폴더 지정
  -o, --output <경로>     기본 출력(CIA/3DS) 폴더 지정
  -l, --lang <ko|en>      표시 언어 지정 (ko 또는 en)
  -h, --help              도움말 표시

환경변수 CIA_INPUT_DIR, CIA_EXTRACTED_DIR, CIA_OUTPUT_DIR, CIA_LANG 도 지원합니다.
EOF
    else
        cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -i, --input <path>      Set default input (CIA) folder
  -e, --extracted <path>  Set extraction (Extracted) working folder
  -o, --output <path>     Set default output (CIA/3DS) folder
  -l, --lang <ko|en>      Set display language (ko or en)
  -h, --help              Show this help message

Environment variables CIA_INPUT_DIR, CIA_EXTRACTED_DIR, CIA_OUTPUT_DIR, CIA_LANG are also supported.
EOF
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--input)
                [[ $# -ge 2 ]] || die "$(msgf "%s 옵션에 경로가 필요합니다." "Option %s requires a path." "$1")"
                INPUT_DIR="$(resolve_dir_path "$2" "$ORIG_PWD")"
                shift 2
                ;;
            -e|--extracted)
                [[ $# -ge 2 ]] || die "$(msgf "%s 옵션에 경로가 필요합니다." "Option %s requires a path." "$1")"
                EXTRACTED_DIR="$(resolve_dir_path "$2" "$ORIG_PWD")"
                shift 2
                ;;
            -o|--output)
                [[ $# -ge 2 ]] || die "$(msgf "%s 옵션에 경로가 필요합니다." "Option %s requires a path." "$1")"
                OUTPUT_DIR="$(resolve_dir_path "$2" "$ORIG_PWD")"
                shift 2
                ;;
            -l|--lang)
                [[ $# -ge 2 ]] || die "Option $1 requires a language code (ko or en)."
                case "$2" in
                    ko|KO) LANG_CODE="ko" ;;
                    en|EN) LANG_CODE="en" ;;
                    *) die "Unknown language code: $2 (use ko or en)" ;;
                esac
                shift 2
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                die "$(msgf "알 수 없는 옵션: %s (--help 로 도움말 확인)" "Unknown option: %s (use --help for usage)" "$1")"
                ;;
        esac
    done
}

init_dirs() {
    local d
    for d in "$INPUT_DIR" "$EXTRACTED_DIR" "$OUTPUT_DIR"; do
        if [[ "$d" == "$SCRIPT_DIR"/* ]]; then
            mkdir -p "$d" || die "$(msgf "디렉토리 생성 실패: %s" "Failed to create directory: %s" "$d")"
        fi
    done
}

check_tools() {
    local missing=""
    [[ -x "$THREE"   ]] || missing+=" 3dstool"
    [[ -x "$CTR"     ]] || missing+=" ctrtool"
    [[ -x "$MAKEROM" ]] || missing+=" makerom"
    [[ -x "$CIAUNIX" ]] || missing+=" cia-unix"
    [[ -n "$missing" ]] && die "$(msgf "다음 도구가 없습니다:%s" "Missing required tools:%s" "$missing")"
}

# 복호화 키 파일 인식 상태 요약 (ext_kry.txt / ext_key.txt 포함)
detect_key_files() {
    local -a found=()
    local k
    for k in ext_kry.txt ext_key.txt seeddb.bin boot9.bin aes_keys.txt encseed.bin ctrdecrypt; do
        [[ -e "$SCRIPT_DIR/$k" ]] && found+=("$k")
    done
    local warn_note=""
    if [[ ! -e "$SCRIPT_DIR/ext_kry.txt" && ! -e "$SCRIPT_DIR/ext_key.txt" ]]; then
        warn_note="$(msg " (주의: ext_kry.txt 없음)" " (Warning: ext_kry.txt missing)")"
    fi
    if [[ "${#found[@]}" -eq 0 ]]; then
        msgf "없음%s" "None%s" "$warn_note"
    else
        local IFS=", "
        printf '%s%s' "${found[*]}" "$warn_note"
    fi
}

# 대소문자 구분 없는 파일시스템(macOS/WSL) 중복 방지
list_cia_in() {
    local dir="$1"
    [[ -d "$dir" ]] || return 0
    find -L "$dir" -maxdepth 1 -type f -iname "*.cia" 2>/dev/null | sort
}

list_rom_in() {
    local dir="$1"
    [[ -d "$dir" ]] || return 0
    find -L "$dir" -maxdepth 1 -type f \( -iname "*.cia" -o -iname "*.3ds" -o -iname "*.cci" \) 2>/dev/null | sort
}

# ---------- CIA / 3DS 메타데이터 추출 ----------
# 전역 결과 변수: ROM_TITLE_ID, ROM_PROD_CODE, ROM_MAJOR, ROM_MINOR, ROM_MICRO, ROM_CRYPTO
read_rom_meta() {
    local file="$1"
    ROM_TITLE_ID="?"
    ROM_PROD_CODE="?"
    ROM_MAJOR=0
    ROM_MINOR=0
    ROM_MICRO=0
    ROM_CRYPTO="?"

    [[ -f "$file" ]] || return 1

    local info
    info="$("$CTR" "$file" 2>/dev/null)" || return 1

    local tid pcode ver_line crypto_line vnum=""
    tid="$(printf '%s\n' "$info" | awk -F':' '/Title [Ii][Dd][[:space:]]*:/ {gsub(/[[:space:]]/, "", $2); print $2; exit}')"
    [[ -n "$tid" ]] && ROM_TITLE_ID="$tid"

    pcode="$(printf '%s\n' "$info" | awk -F':' '/Product code[[:space:]]*:/ {gsub(/[[:space:]]/, "", $2); print $2; exit}')"
    [[ -n "$pcode" ]] && ROM_PROD_CODE="$pcode"

    ver_line="$(printf '%s\n' "$info" | awk -F':' '/Title version[[:space:]]*:/ {print $2; exit}')"
    if [[ "$ver_line" =~ ([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        ROM_MAJOR="${BASH_REMATCH[1]}"
        ROM_MINOR="${BASH_REMATCH[2]}"
        ROM_MICRO="${BASH_REMATCH[3]}"
    else
        if [[ "$ver_line" =~ \(([0-9]+)\) ]]; then
            vnum="${BASH_REMATCH[1]}"
        elif [[ "$ver_line" =~ 0[xX]([0-9a-fA-F]+) ]]; then
            vnum=$(( 16#${BASH_REMATCH[1]} ))
        elif [[ "$ver_line" =~ ([0-9]+) ]]; then
            vnum="${BASH_REMATCH[1]}"
        fi
        if [[ -n "$vnum" ]]; then
            ROM_MAJOR=$(( vnum >> 10 ))
            ROM_MINOR=$(( (vnum >> 4) & 63 ))
            ROM_MICRO=$(( vnum & 15 ))
        fi
    fi

    crypto_line="$(printf '%s\n' "$info" | awk -F':' '/Crypto Key[[:space:]]*:/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}')"
    if [[ -n "$crypto_line" ]]; then
        ROM_CRYPTO="$crypto_line"
    elif printf '%s\n' "$info" | grep -qi "Encrypted"; then
        ROM_CRYPTO="Encrypted"
    else
        ROM_CRYPTO="Decrypted / Standard"
    fi
    return 0
}

save_extracted_meta() {
    local dest="$1" src_name="$2"
    printf '%s\n' "$src_name" > "$dest/.source_name"
    cat > "$dest/.source_meta" <<EOF
META_TITLE_ID=$(printf '%q' "$ROM_TITLE_ID")
META_PROD_CODE=$(printf '%q' "$ROM_PROD_CODE")
META_MAJOR=$(printf '%q' "$ROM_MAJOR")
META_MINOR=$(printf '%q' "$ROM_MINOR")
META_MICRO=$(printf '%q' "$ROM_MICRO")
EOF
}

load_extracted_meta() {
    local dir="$1"
    META_TITLE_ID="?"
    META_PROD_CODE="?"
    META_MAJOR=0
    META_MINOR=0
    META_MICRO=0
    [[ -f "$dir/.source_meta" ]] || return 0
    # shellcheck disable=SC1090
    source "$dir/.source_meta" 2>/dev/null || true
    [[ "${META_MAJOR:-}" =~ ^[0-9]+$ ]] || META_MAJOR=0
    [[ "${META_MINOR:-}" =~ ^[0-9]+$ ]] || META_MINOR=0
    [[ "${META_MICRO:-}" =~ ^[0-9]+$ ]] || META_MICRO=0
}

# ---------- 출력 경로 해석 ----------
resolve_out_path() {
    local raw="$1" ext="$2" def_dir="$3" def_name="$4"
    raw="$(normalize_path "$raw")"
    [[ -z "$raw" ]] && raw="$def_name"

    shopt -s nocasematch
    [[ "$raw" == *".$ext" ]] && raw="${raw:0:$((${#raw}-${#ext}-1))}"
    shopt -u nocasematch
    [[ -z "$raw" ]] && raw="$def_name"
    [[ "$raw" == */ ]] && raw="${raw}${def_name}"

    local out
    case "$raw" in
        /*|./*|../*)
            out="${raw}.${ext}"
            ;;
        *)
            out="${def_dir}/${raw}.${ext}"
            ;;
    esac

    local parent="${out%/*}"
    [[ "$parent" == "$out" ]] && parent="."
    [[ -d "$parent" ]] || mkdir -p "$parent" 2>/dev/null || {
        msgf "ERROR: 디렉토리 생성 실패: %s\n" "ERROR: Failed to create directory: %s\n" "$parent" >&2
        return 1
    }
    printf '%s\n' "$out"
}

confirm_overwrite() {
    local path="$1"
    [[ -e "$path" ]] || return 0
    local ans prompt
    prompt="$(msgf "  ⚠ 이미 존재합니다: %s — 덮어쓸까요? (y/N): " "  ⚠ Already exists: %s — Overwrite? (y/N): " "${path#$SCRIPT_DIR/}")"
    if ! read -rp "$prompt" ans; then
        printf '\n' >&2
        return 1
    fi
    is_yes "$ans"
}

# ---------- 파일 선택 (p = 직접 경로) ----------
prompt_custom_file() {
    local custom dir base prompt
    prompt="$(msg "파일 경로 (빈칸=취소): " "File path (blank=cancel): ")"
    while true; do
        if ! read_line_edit "$prompt" custom; then
            printf '\n' >&2
            return 1
        fi
        custom="$(normalize_path "$custom")"
        [[ -z "$custom" ]] && return 1

        if [[ -f "$custom" ]]; then
            dir="$(cd "$(dirname "$custom")" 2>/dev/null && pwd)" || {
                msgf "경로에 접근할 수 없습니다: %s\n" "Cannot access path: %s\n" "$custom" >&2
                continue
            }
            base="$(basename "$custom")"
            printf '%s/%s\n' "$dir" "$base"
            return 0
        fi
        msgf "파일이 존재하지 않습니다: %s\n" "File does not exist: %s\n" "$custom" >&2
    done
}

pick_file() {
    local title="$1"; shift
    local -a files=("$@")
    local n=${#files[@]}
    local i ans rel prompt

    if [[ "$n" -eq 0 ]]; then
        say "  지정된 폴더에 대상 파일이 없어 직접 경로를 입력합니다." \
            "  No target files found in the folder. Please enter a file path manually." >&2
        prompt_custom_file || printf '\n'
        return
    fi

    if [[ "$n" -eq 1 ]]; then
        rel="${files[0]#$SCRIPT_DIR/}"
        prompt="$(msgf "  파일 발견: %s (Enter=선택, p=직접 경로, 0=취소): " "  File found: %s (Enter=select, p=custom path, 0=cancel): " "$rel")"
        echo >&2
        while true; do
            if ! read -rp "$prompt" ans; then
                printf '\n' >&2
                return
            fi
            case "$ans" in
                "")
                    printf '%s\n' "${files[0]}"
                    return
                    ;;
                0)
                    printf '\n'
                    return
                    ;;
                p|P)
                    prompt_custom_file || printf '\n'
                    return
                    ;;
                *)
                    say "잘못된 입력입니다." "Invalid input." >&2
                    ;;
            esac
        done
    fi

    {
        echo
        echo "$title"
        for i in "${!files[@]}"; do
            rel="${files[i]#$SCRIPT_DIR/}"
            printf "  %d) %s\n" "$((i+1))" "$rel"
        done
        say "  p) 직접 경로 입력" "  p) Enter custom path"
        echo
    } >&2

    prompt="$(msg "번호 선택 (0=취소, p=직접 경로): " "Select number (0=cancel, p=custom path): ")"
    while true; do
        if ! read -rp "$prompt" ans; then
            printf '\n' >&2
            return
        fi
        [[ "$ans" == "0" ]] && { printf '\n'; return; }
        if [[ "$ans" == "p" || "$ans" == "P" ]]; then
            prompt_custom_file || printf '\n'
            return
        fi
        if [[ "$ans" =~ ^[0-9]+$ ]] && (( ans >= 1 && ans <= n )); then
            printf '%s\n' "${files[$((ans-1))]}"
            return
        fi
        say "잘못된 입력입니다." "Invalid input." >&2
    done
}

# ---------- Work & Extracted 정리 ----------
prepare_work() {
    validate_safe_dir "$WORK_DIR" "WORK_DIR"
    rm -rf -- "$WORK_DIR"
    mkdir -p "$WORK_DIR" || die "$(msgf "Work 생성 실패: %s" "Failed to create Work folder: %s" "$WORK_DIR")"
}

clean_work() {
    validate_safe_dir "$WORK_DIR" "WORK_DIR"
    rm -rf -- "$WORK_DIR"
}

clean_extracted() {
    validate_safe_dir "$EXTRACTED_DIR" "EXTRACTED_DIR"
    [[ -d "$EXTRACTED_DIR" ]] || return 0
    [[ -n "$(ls -A "$EXTRACTED_DIR" 2>/dev/null)" ]] || return 0

    # 분해 작업 흔적이 없는 일반 폴더를 실수로 지정했을 경우 이중 확인
    if [[ ! -f "$EXTRACTED_DIR/.source_name" && \
          ! -f "$EXTRACTED_DIR/HeaderNCCH0.bin" && \
          ! -d "$EXTRACTED_DIR/ExeFS" && \
          ! -d "$EXTRACTED_DIR/RomFS" ]]; then
        local extra_ans prompt
        warn "$(msgf "이 폴더에는 기존 CIA 분해 흔적이 없습니다: %s" "This folder has no previous CIA extraction markers: %s" "$EXTRACTED_DIR")"
        prompt="$(msg "  일반 파일이 영구 삭제될 수 있습니다. 정말 비울까요? (y/N): " "  Regular files may be permanently deleted. Empty anyway? (y/N): ")"
        read -rp "$prompt" extra_ans
        is_yes "$extra_ans" || return 1
    fi

    rm -rf -- "$EXTRACTED_DIR"/* "$EXTRACTED_DIR"/.[!.]* "$EXTRACTED_DIR"/..?* 2>/dev/null || true
}

# ---------- cia-unix 실행 ----------
cia_unix_convert() {
    local cia="$1" out="$2"
    local log="$WORK_DIR/ciaunix.log"
    local cia_filename cia_stem escaped_stem
    cia_filename="$(basename "$cia")"
    cia_stem="${cia_filename%.*}"
    escaped_stem="$(printf '%s' "$cia_stem" | sed 's/[][*?\\]/\\&/g')"
    prepare_work

    local t
    for t in cia-unix ctrtool makerom 3dstool ctrdecrypt \
             ext_kry.txt ext_key.txt seeddb.bin dltools.sh aes_keys.txt boot9.bin encseed.bin; do
        [[ -e "$SCRIPT_DIR/$t" ]] && ln -sf -- "$SCRIPT_DIR/$t" "$WORK_DIR/$t"
    done
    # 공백·괄호가 포함된 원본 파일명으로 인한 cia-unix 내부 오류 방지를 위해 고정 이름 사용
    ln -sf -- "$cia" "$WORK_DIR/input.cia"

    msgf "  작업 공간: %s\n" "  Workspace: %s\n" "$WORK_DIR"
    say  "  실행 중..." "  Running..."
    echo "  ──────────────────────────────────────────"

    (
        cd "$WORK_DIR" || exit 99
        export PATH="$SCRIPT_DIR:$PATH"
        if command -v script >/dev/null 2>&1; then
            if script -q -c true /dev/null >/dev/null 2>&1; then
                script -q -e -c "./cia-unix" "$log"
            else
                script -q "$log" ./cia-unix
            fi
        else
            ./cia-unix 2>&1 | tee -a "$log"
        fi
    )
    local rc=$?

    echo "  ──────────────────────────────────────────"
    msgf "  종료코드: %s\n" "  Exit code: %s\n" "$rc"

    local generated=""
    generated=$(find "$WORK_DIR" -maxdepth 1 -type f -size +0c \
        \( -iname "*.3ds" -o -iname "*.cci" \) 2>/dev/null | head -n1)
    if [[ -z "$generated" ]]; then
        generated=$(find "$(dirname "$cia")" -maxdepth 1 -type f -size +0c \
            \( -iname "input*.3ds" -o -iname "input*.cci" -o -iname "${escaped_stem}*.3ds" -o -iname "${escaped_stem}*.cci" \) \
            -newer "$cia" 2>/dev/null | head -n1)
    fi

    if [[ "$rc" -ne 0 || -z "$generated" ]]; then
        if [[ "$rc" -ne 0 ]]; then
            msgf "  ✗ cia-unix가 비정상 종료되었습니다 (종료코드: %s).\n" "  ✗ cia-unix exited abnormally (exit code: %s).\n" "$rc"
        else
            say "  ✗ 출력 파일을 찾을 수 없습니다." "  ✗ Output file not found."
        fi
        say "  [디버그] Work:" "  [Debug] Work:"
        ls -la "$WORK_DIR" 2>/dev/null | awk 'NR>1 && $NF!="." && $NF!=".." {printf "    %-40s %10s bytes\n", $NF, $5}'
        [[ -s "$log" ]] && { say "  [디버그] 로그 (끝 20줄):" "  [Debug] Log (last 20 lines):"; tail -n 20 "$log"; }
        msgf "  ※ Work 폴더 보존: %s\n" "  * Work folder preserved: %s\n" "$WORK_DIR"
        return 1
    fi

    mv -f -- "$generated" "$out" || { clean_work; return 1; }
    clean_work
    return 0
}

# ---------- 파티션 추출 ----------
extract_partitions() {
    local input="$1" dest="$2"

    say "  모든 파티션 추출..." "  Extracting all partitions..."
    if ! run_tool "$THREE" -xvt01267f cci \
        "$dest/DecryptedPartition0.bin" "$dest/DecryptedPartition1.bin" \
        "$dest/DecryptedPartition2.bin" "$dest/DecryptedPartition6.bin" \
        "$dest/DecryptedPartition7.bin" \
        "$input" --header "$dest/HeaderNCSD.bin"; then
        warn "$(msg "3dstool -xvt01267f cci 실패" "3dstool -xvt01267f cci failed")"; return 1
    fi

    if [[ -s "$dest/DecryptedPartition0.bin" ]]; then
        say "  NCCH0 분해..." "  Extracting NCCH0..."
        if ! run_tool "$THREE" -xvtf cxi "$dest/DecryptedPartition0.bin" \
            --header "$dest/HeaderNCCH0.bin" \
            --exh "$dest/DecryptedExHeader.bin" --exh-auto-key \
            --exefs "$dest/DecryptedExeFS.bin" --exefs-auto-key --exefs-top-auto-key \
            --romfs "$dest/DecryptedRomFS.bin" --romfs-auto-key \
            --logo "$dest/LogoLZ.bin" --plain "$dest/PlainRGN.bin"; then
            warn "$(msg "NCCH0 분해 실패" "NCCH0 extraction failed")"; return 1
        fi
        if [[ -s "$dest/DecryptedExeFS.bin" ]]; then
            say "  ExeFS 추출..." "  Extracting ExeFS..."
            "$THREE" -xvtf exefs "$dest/DecryptedExeFS.bin" \
                --header "$dest/HeaderExeFS.bin" \
                --exefs-dir "$dest/ExeFS" >/dev/null 2>&1 \
                || run_tool "$CTR" -t exefs --exefsdir="$dest/ExeFS" "$dest/DecryptedExeFS.bin" --decompresscode \
                || warn "$(msg "ExeFS 추출 실패" "ExeFS extraction failed")"
        fi
        if [[ -s "$dest/DecryptedRomFS.bin" ]]; then
            say "  RomFS 추출..." "  Extracting RomFS..."
            "$THREE" -xvtf romfs "$dest/DecryptedRomFS.bin" --romfs-dir "$dest/RomFS" >/dev/null 2>&1 \
                || run_tool "$CTR" -t romfs --romfsdir="$dest/RomFS" "$dest/DecryptedRomFS.bin" \
                || warn "$(msg "RomFS 추출 실패" "RomFS extraction failed")"
        fi
    fi

    if [[ -s "$dest/DecryptedPartition1.bin" ]]; then
        say "  NCCH1(Manual) 분해..." "  Extracting NCCH1 (Manual)..."
        "$THREE" -xvtf cfa "$dest/DecryptedPartition1.bin" \
            --header "$dest/HeaderNCCH1.bin" \
            --romfs "$dest/DecryptedManual.bin" --romfs-auto-key >/dev/null 2>&1 \
            && "$THREE" -xvtf romfs "$dest/DecryptedManual.bin" --romfs-dir "$dest/Manual" >/dev/null 2>&1 \
            || warn "$(msg "Manual 분해 실패 (건너뜀)" "Manual extraction failed (skipped)")"
    fi
    if [[ -s "$dest/DecryptedPartition2.bin" ]]; then
        say "  NCCH2(DownloadPlay) 분해..." "  Extracting NCCH2 (DownloadPlay)..."
        "$THREE" -xvtf cfa "$dest/DecryptedPartition2.bin" \
            --header "$dest/HeaderNCCH2.bin" \
            --romfs "$dest/DecryptedDownloadPlay.bin" --romfs-auto-key >/dev/null 2>&1 \
            && "$THREE" -xvtf romfs "$dest/DecryptedDownloadPlay.bin" --romfs-dir "$dest/DownloadPlay" >/dev/null 2>&1 \
            || warn "$(msg "DownloadPlay 분해 실패 (건너뜀)" "DownloadPlay extraction failed (skipped)")"
    fi

    rm -f -- "$dest/DecryptedPartition"{0,1,2,6,7}.bin \
          "$dest/DecryptedExeFS.bin" "$dest/DecryptedRomFS.bin" \
          "$dest/DecryptedManual.bin" "$dest/DecryptedDownloadPlay.bin" \
          "$dest/HeaderNCSD.bin"

    [[ -f "$dest/ExeFS/banner.bnr" ]] && mv -f -- "$dest/ExeFS/banner.bnr" "$dest/ExeFS/banner.bin"
    [[ -f "$dest/ExeFS/icon.icn" ]] && mv -f -- "$dest/ExeFS/icon.icn" "$dest/ExeFS/icon.bin"
    return 0
}

# ---------- 메뉴 1: 분해 ----------
menu_extract() {
    echo; say "=== CIA 분해 ===" "=== Extract CIA ==="; echo
    local -a cias=()
    local f ans prompt
    while IFS= read -r f; do [[ -n "$f" ]] && cias+=("$f"); done < <(list_cia_in "$INPUT_DIR")

    local cia title
    title="$(msgf "대상 CIA 파일 (%s):" "Target CIA file (%s):" "$INPUT_DIR")"
    cia=$(pick_file "$title" ${cias[@]+"${cias[@]}"})
    [[ -z "$cia" ]] && { say "취소했습니다." "Cancelled."; pause; return; }

    echo
    say "추출할 대상 폴더 (빈칸 = 현재 설정 경로 사용, 이번 세션만 적용)" \
        "Destination folder (blank = use current setting, applies to this session only)"
    local ext_raw target_ext
    prompt="$(msgf "추출 폴더 [%s]: " "Extract folder [%s]: " "$EXTRACTED_DIR")"
    if ! read_line_edit "$prompt" ext_raw; then
        say "취소했습니다." "Cancelled."; pause; return
    fi
    if [[ -n "$(normalize_path "$ext_raw")" ]]; then
        target_ext="$(resolve_dir_path "$ext_raw" "$SCRIPT_DIR")"
        validate_safe_dir "$target_ext" "$(msg "추출 폴더" "extract folder")"
        EXTRACTED_DIR="$target_ext"
    fi

    mkdir -p "$EXTRACTED_DIR" || {
        warn "$(msgf "추출 폴더 생성 실패: %s" "Failed to create extract folder: %s" "$EXTRACTED_DIR")"
        pause; return
    }

    if [[ -n "$(ls -A "$EXTRACTED_DIR" 2>/dev/null)" ]]; then
        echo
        msgf "대상 폴더에 기존 파일이 있습니다: %s\n" "Destination folder already contains files: %s\n" "$EXTRACTED_DIR"
        prompt="$(msg "삭제하고 새로 추출할까요? (y/N): " "Delete existing files and extract? (y/N): ")"
        read -rp "$prompt" ans
        is_yes "$ans" || { say "취소했습니다." "Cancelled."; pause; return; }
        clean_extracted || { say "취소했습니다." "Cancelled."; pause; return; }
    fi

    local source_name
    source_name="$(basename "${cia%.*}")"
    read_rom_meta "$cia" || true
    save_extracted_meta "$EXTRACTED_DIR" "$source_name"
    msgf "  메타데이터: TitleID=%s / Code=%s / v%s.%s.%s\n" \
         "  Metadata: TitleID=%s / Code=%s / v%s.%s.%s\n" \
         "$ROM_TITLE_ID" "$ROM_PROD_CODE" "$ROM_MAJOR" "$ROM_MINOR" "$ROM_MICRO"

    echo
    say "[1/3] cia-unix로 CIA → 3DS 변환..." "[1/3] Converting CIA → 3DS via cia-unix..."
    local temp_3ds="$EXTRACTED_DIR/.temp_decrypted.3ds"
    if ! cia_unix_convert "$cia" "$temp_3ds"; then
        rm -f -- "$EXTRACTED_DIR/.source_name" "$EXTRACTED_DIR/.source_meta" "$temp_3ds"
        warn "$(msg "cia-unix 변환 실패" "cia-unix conversion failed")"; pause; return
    fi
    echo "  → $(file_size "$temp_3ds") bytes"

    say "[2/3] 3DS에서 파티션/컨텐츠 추출..." "[2/3] Extracting partitions/contents from 3DS..."
    if ! extract_partitions "$temp_3ds" "$EXTRACTED_DIR"; then
        rm -f -- "$temp_3ds"
        warn "$(msg "파티션 추출 실패" "Partition extraction failed")"; pause; return
    fi

    say "[3/3] 임시 파일 정리..." "[3/3] Cleaning temporary files..."
    rm -f -- "$temp_3ds"

    echo
    msgf "분해 완료: %s\n" "Extraction complete: %s\n" "$EXTRACTED_DIR"
    msgf "  ExeFS: %s 파일\n" "  ExeFS: %s files\n" "$(find "$EXTRACTED_DIR/ExeFS" -type f 2>/dev/null | wc -l | tr -d ' ')"
    msgf "  RomFS: %s 파일\n" "  RomFS: %s files\n" "$(find "$EXTRACTED_DIR/RomFS" -type f 2>/dev/null | wc -l | tr -d ' ')"
    pause_with_open "$EXTRACTED_DIR" "$(msg "Extracted 폴더 열기" "Open Extracted folder")"
}

# ---------- 메뉴 2: 재구성 ----------
menu_rebuild() {
    echo; say "=== CIA 재구성 ===" "=== Rebuild CIA ==="; echo
    say "분해된 원본 폴더 (빈칸 = 현재 설정 경로 사용, 이번 세션만 적용)" \
        "Extracted source folder (blank = use current setting, applies to this session only)"
    local ext_raw prompt
    prompt="$(msgf "원본 폴더 [%s]: " "Source folder [%s]: " "$EXTRACTED_DIR")"
    if ! read_line_edit "$prompt" ext_raw; then
        say "취소했습니다." "Cancelled."; pause; return
    fi
    if [[ -n "$(normalize_path "$ext_raw")" ]]; then
        local custom_ext
        custom_ext="$(resolve_dir_path "$ext_raw" "$SCRIPT_DIR")"
        if [[ ! -d "$custom_ext" ]]; then
            warn "$(msgf "폴더가 존재하지 않습니다: %s" "Folder does not exist: %s" "$custom_ext")"
            pause; return
        fi
        EXTRACTED_DIR="$custom_ext"
    fi

    [[ -f "$EXTRACTED_DIR/HeaderNCCH0.bin" ]] || {
        msgf "HeaderNCCH0.bin 없음 (%s). 먼저 분해하세요.\n" "HeaderNCCH0.bin missing (%s). Extract a CIA first.\n" "$EXTRACTED_DIR"
        pause; return
    }
    [[ -f "$EXTRACTED_DIR/DecryptedExHeader.bin" ]] || {
        msgf "DecryptedExHeader.bin 없음 (%s).\n" "DecryptedExHeader.bin missing (%s).\n" "$EXTRACTED_DIR"
        pause; return
    }
    [[ -d "$EXTRACTED_DIR/ExeFS" ]] || {
        msgf "ExeFS/ 폴더 없음 (%s).\n" "ExeFS/ folder missing (%s).\n" "$EXTRACTED_DIR"
        pause; return
    }

    local source_name="edited"
    [[ -f "$EXTRACTED_DIR/.source_name" ]] && source_name="$(cat "$EXTRACTED_DIR/.source_name")"
    load_extracted_meta "$EXTRACTED_DIR"

    echo
    say "출력 파일명" "Output filename"
    msgf "  · 이름만 입력        → %s/이름.cia\n" "  · Name only          → %s/name.cia\n" "$OUTPUT_DIR"
    msgf "  · 하위 폴더 포함     → %s/하위폴더/이름.cia\n" "  · With subfolder     → %s/subfolder/name.cia\n" "$OUTPUT_DIR"
    say  "  · / 또는 ~/ 로 시작  → 해당 절대/홈 경로 그대로 사용" "  · Starts with / or ~ → Use exact absolute/home path"
    msgf "  · 빈칸               → %s_Edited.cia\n" "  · Blank              → %s_Edited.cia\n" "$source_name"
    local out_raw
    prompt="$(msgf "이름 [%s_Edited]: " "Name [%s_Edited]: " "$source_name")"
    read_line_edit "$prompt" out_raw || { say "취소했습니다." "Cancelled."; pause; return; }

    local out_cia
    out_cia="$(resolve_out_path "$out_raw" "cia" "$OUTPUT_DIR" "${source_name}_Edited")" || {
        warn "$(msg "출력 경로 생성 실패" "Failed to resolve output path")"; pause; return
    }
    if ! confirm_overwrite "$out_cia"; then
        say "취소했습니다." "Cancelled."; pause; return
    fi

    local major minor micro ans
    read -rp "$(msgf "major 버전 [원본: %s]: " "major version [original: %s]: " "$META_MAJOR")" major
    read -rp "$(msgf "minor 버전 [원본: %s]: " "minor version [original: %s]: " "$META_MINOR")" minor
    read -rp "$(msgf "micro 버전 [원본: %s]: " "micro version [original: %s]: " "$META_MICRO")" micro
    major="${major:-$META_MAJOR}"
    minor="${minor:-$META_MINOR}"
    micro="${micro:-$META_MICRO}"
    if ! [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ && "$micro" =~ ^[0-9]+$ ]]; then
        warn "$(msgf "버전은 정수여야 합니다 (입력: major='%s', minor='%s', micro='%s')." \
                    "Version numbers must be integers (got: major='%s', minor='%s', micro='%s')." \
                    "$major" "$minor" "$micro")"
        pause; return
    fi

    if rebuild_cia_impl "$out_cia" "$major" "$minor" "$micro"; then
        echo
        msgf "생성: %s (%s bytes)\n" "Created: %s (%s bytes)\n" "$out_cia" "$(file_size "$out_cia")"
        echo
        prompt="$(msgf "분해 폴더(%s)를 정리할까요? (y/N): " "Clean up extracted folder (%s)? (y/N): " "$EXTRACTED_DIR")"
        read -rp "$prompt" ans
        if is_yes "$ans"; then
            clean_extracted && say "정리했습니다." "Cleaned up."
        fi
        pause_with_open "$(dirname "$out_cia")" "$(msg "출력 폴더 열기" "Open output folder")"
    else
        echo
        warn "$(msg "재구성에 실패했습니다." "Rebuild failed.")"
        [[ -d "$WORK_DIR" ]] && msgf "  Work/ 폴더 확인: %s\n" "  Check Work/ folder: %s\n" "$WORK_DIR"
        pause
    fi
}

rebuild_cia_impl() {
    local out_cia="$1" major="$2" minor="$3" micro="$4"
    local src="$EXTRACTED_DIR"
    prepare_work

    local banner_back=0 icon_back=0
    restore_exefs_names() {
        [[ "$banner_back" == 1 && -f "$src/ExeFS/banner.bnr" ]] && mv -f -- "$src/ExeFS/banner.bnr" "$src/ExeFS/banner.bin"
        [[ "$icon_back"   == 1 && -f "$src/ExeFS/icon.icn"   ]] && mv -f -- "$src/ExeFS/icon.icn"   "$src/ExeFS/icon.bin"
        banner_back=0
        icon_back=0
    }
    trap 'restore_exefs_names; trap - INT TERM; kill -INT $$' INT
    trap 'restore_exefs_names; trap - INT TERM; kill -TERM $$' TERM

    [[ -f "$src/ExeFS/banner.bin" ]] && mv -f -- "$src/ExeFS/banner.bin" "$src/ExeFS/banner.bnr" && banner_back=1
    [[ -f "$src/ExeFS/icon.bin" ]]   && mv -f -- "$src/ExeFS/icon.bin"   "$src/ExeFS/icon.icn" && icon_back=1

    echo
    say "[1/5] ExeFS 빌드..." "[1/5] Building ExeFS..."
    local exefs_ok=0
    if [[ -f "$src/HeaderExeFS.bin" ]]; then
        "$THREE" -cvtf exefs "$WORK_DIR/CustomExeFS.bin" \
            --exefs-dir "$src/ExeFS" --header "$src/HeaderExeFS.bin" >/dev/null 2>&1 && exefs_ok=1
    fi
    if [[ "$exefs_ok" -eq 0 ]]; then
        if ! run_tool "$THREE" -cvtf exefs "$WORK_DIR/CustomExeFS.bin" --exefs-dir "$src/ExeFS"; then
            restore_exefs_names
            trap - INT TERM
            clean_work; warn "$(msg "ExeFS 빌드 실패" "ExeFS build failed")"; return 1
        fi
    fi
    restore_exefs_names
    trap - INT TERM

    say "[2/5] RomFS 빌드..." "[2/5] Building RomFS..."
    if [[ -d "$src/RomFS" ]] && [[ -n "$(find "$src/RomFS" -type f 2>/dev/null | head -n1)" ]]; then
        if ! run_tool "$THREE" -cvtf romfs "$WORK_DIR/CustomRomFS.bin" --romfs-dir "$src/RomFS"; then
            clean_work; warn "$(msg "RomFS 빌드 실패" "RomFS build failed")"; return 1
        fi
    fi

    say "[3/5] CXI(NCCH0) 빌드..." "[3/5] Building CXI (NCCH0)..."
    local cxi_args=(-cvtf cxi "$WORK_DIR/CustomPartition0.bin"
        --header "$src/HeaderNCCH0.bin"
        --exh "$src/DecryptedExHeader.bin" --exh-auto-key
        --exefs "$WORK_DIR/CustomExeFS.bin" --exefs-auto-key --exefs-top-auto-key)
    [[ -s "$WORK_DIR/CustomRomFS.bin" ]] && cxi_args+=(--romfs "$WORK_DIR/CustomRomFS.bin" --romfs-auto-key)
    [[ -s "$src/LogoLZ.bin" ]] && cxi_args+=(--logo "$src/LogoLZ.bin")
    [[ -s "$src/PlainRGN.bin" ]] && cxi_args+=(--plain "$src/PlainRGN.bin")

    if ! "$THREE" "${cxi_args[@]}" >/dev/null 2>&1; then
        warn "$(msg "CXI 빌드 실패 → 빈 Logo/Plain 재시도..." "CXI build failed → Retrying with empty Logo/Plain...")"
        : > "$WORK_DIR/empty_logo.bin"; : > "$WORK_DIR/empty_plain.bin"
        cxi_args=(-cvtf cxi "$WORK_DIR/CustomPartition0.bin"
            --header "$src/HeaderNCCH0.bin"
            --exh "$src/DecryptedExHeader.bin" --exh-auto-key
            --exefs "$WORK_DIR/CustomExeFS.bin" --exefs-auto-key --exefs-top-auto-key
            --logo "$WORK_DIR/empty_logo.bin" --plain "$WORK_DIR/empty_plain.bin")
        [[ -s "$WORK_DIR/CustomRomFS.bin" ]] && cxi_args+=(--romfs "$WORK_DIR/CustomRomFS.bin" --romfs-auto-key)
        if ! run_tool "$THREE" "${cxi_args[@]}"; then
            msgf "  ※ Work 보존: %s\n" "  * Work preserved: %s\n" "$WORK_DIR"
            warn "$(msg "CXI 최종 실패" "CXI build failed")"; return 1
        fi
    fi

    say "[4/5] 선택 파티션 빌드..." "[4/5] Building optional partitions..."
    if [[ -f "$src/HeaderNCCH1.bin" && -d "$src/Manual" ]] && \
       [[ -n "$(find "$src/Manual" -type f 2>/dev/null | head -n1)" ]]; then
        "$THREE" -cvtf romfs "$WORK_DIR/CustomManual.bin" --romfs-dir "$src/Manual" >/dev/null 2>&1 \
            && "$THREE" -cvtf cfa "$WORK_DIR/CustomPartition1.bin" \
                --header "$src/HeaderNCCH1.bin" \
                --romfs "$WORK_DIR/CustomManual.bin" --romfs-auto-key >/dev/null 2>&1 \
            || warn "$(msg "Manual 파티션 빌드 실패 (건너뜀)" "Manual partition build failed (skipped)")"
    fi
    if [[ -f "$src/HeaderNCCH2.bin" && -d "$src/DownloadPlay" ]] && \
       [[ -n "$(find "$src/DownloadPlay" -type f 2>/dev/null | head -n1)" ]]; then
        "$THREE" -cvtf romfs "$WORK_DIR/CustomDownloadPlay.bin" --romfs-dir "$src/DownloadPlay" >/dev/null 2>&1 \
            && "$THREE" -cvtf cfa "$WORK_DIR/CustomPartition2.bin" \
                --header "$src/HeaderNCCH2.bin" \
                --romfs "$WORK_DIR/CustomDownloadPlay.bin" --romfs-auto-key >/dev/null 2>&1 \
            || warn "$(msg "DownloadPlay 파티션 빌드 실패 (건너뜀)" "DownloadPlay partition build failed (skipped)")"
    fi

    say "[5/5] makerom으로 CIA 패키징..." "[5/5] Packaging CIA with makerom..."
    local tmp_cia="$WORK_DIR/final.cia"
    local mr_args=(-f cia -o "$tmp_cia" -ignoresign -target p
        -content "$WORK_DIR/CustomPartition0.bin:0:0x00")
    [[ -s "$WORK_DIR/CustomPartition1.bin" ]] && mr_args+=(-content "$WORK_DIR/CustomPartition1.bin:1:0x01")
    [[ -s "$WORK_DIR/CustomPartition2.bin" ]] && mr_args+=(-content "$WORK_DIR/CustomPartition2.bin:2:0x02")
    mr_args+=(-major "$major" -minor "$minor" -micro "$micro")

    if ! "$MAKEROM" "${mr_args[@]}" 2>&1 | tee "$WORK_DIR/makerom.log"; then
        msgf "  ※ Work 보존: %s\n" "  * Work preserved: %s\n" "$WORK_DIR"; return 1
    fi
    [[ -s "$tmp_cia" ]] || { msgf "  ※ Work 보존: %s\n" "  * Work preserved: %s\n" "$WORK_DIR"; return 1; }

    mv -f -- "$tmp_cia" "$out_cia" || { warn "$(msg "출력 이동 실패" "Failed to move output file")"; return 1; }
    clean_work
    return 0
}

# ---------- 메뉴 3: 변환 (단일 / 일괄) ----------
batch_convert_input() {
    local -a in_cias=()
    local f
    while IFS= read -r f; do [[ -n "$f" ]] && in_cias+=("$f"); done < <(list_cia_in "$INPUT_DIR")

    local total=${#in_cias[@]}
    if [[ "$total" -eq 0 ]]; then
        warn "$(msgf "Input 폴더(%s)에 변환할 .cia 파일이 없습니다." "No .cia files found in Input folder (%s)." "$INPUT_DIR")"
        pause; return
    fi

    mkdir -p "$OUTPUT_DIR" || {
        warn "$(msgf "출력 폴더 생성 실패: %s" "Failed to create output folder: %s" "$OUTPUT_DIR")"
        pause; return
    }

    echo
    msgf "Input 폴더의 CIA %s개를 모두 %s 로 변환합니다.\n" \
         "Converting all %s CIA files from Input to %s.\n" \
         "$total" "$OUTPUT_DIR"
    local mode_ans overwrite_all=0 prompt
    prompt="$(msg "기존 .3ds 파일이 있을 때 처리 방식 (s=건너뛰기, o=모두 덮어쓰기, 0=취소) [s]: " \
                  "When .3ds already exists (s=skip, o=overwrite all, 0=cancel) [s]: ")"
    read -rp "$prompt" mode_ans
    case "$mode_ans" in
        0) say "취소했습니다." "Cancelled."; pause; return ;;
        o|O) overwrite_all=1 ;;
        ""|s|S) overwrite_all=0 ;;
        *) say "잘못된 입력입니다." "Invalid input."; pause; return ;;
    esac

    local idx=0 ok=0 skip=0 fail=0 base out_3ds
    for f in "${in_cias[@]}"; do
        ((idx++))
        base="$(basename "${f%.*}")"
        out_3ds="$OUTPUT_DIR/${base}.3ds"
        echo
        echo "=== [$idx/$total] $(basename "$f") ==="
        if [[ -e "$out_3ds" && "$overwrite_all" -eq 0 ]]; then
            msgf "  이미 존재하여 건너뜁니다: %s\n" "  Already exists, skipping: %s\n" "$out_3ds"
            ((skip++))
            continue
        fi
        if cia_unix_convert "$f" "$out_3ds"; then
            msgf "  ✓ 완료: %s (%s bytes)\n" "  ✓ Done: %s (%s bytes)\n" "$out_3ds" "$(file_size "$out_3ds")"
            ((ok++))
        else
            warn "$(msgf "실패: %s" "Failed: %s" "$(basename "$f")")"
            ((fail++))
        fi
    done

    echo
    echo "=================================================="
    msgf " 일괄 변환 완료 — 성공: %s개 / 건너뜀: %s개 / 실패: %s개\n" \
         " Batch convert complete — OK: %s / Skipped: %s / Failed: %s\n" \
         "$ok" "$skip" "$fail"
    echo "=================================================="
    pause_with_open "$OUTPUT_DIR" "$(msg "Output 폴더 열기" "Open Output folder")"
}

menu_convert() {
    echo; say "=== CIA → 3DS 변환 ===" "=== Convert CIA → 3DS ==="; echo
    local -a in_cias=() all_cias=()
    local f existing already prompt
    while IFS= read -r f; do
        [[ -n "$f" ]] && { in_cias+=("$f"); all_cias+=("$f"); }
    done < <(list_cia_in "$INPUT_DIR")

    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        already=0
        for existing in ${all_cias[@]+"${all_cias[@]}"}; do
            [[ "$existing" == "$f" ]] && { already=1; break; }
        done
        [[ "$already" -eq 0 ]] && all_cias+=("$f")
    done < <(list_cia_in "$OUTPUT_DIR")

    if [[ "${#in_cias[@]}" -ge 2 ]]; then
        say "  1) 개별 파일 선택 변환" "  1) Convert a single file"
        msgf "  a) Input 폴더의 모든 CIA 일괄 변환 (%s개 → %s)\n" \
             "  a) Batch convert all CIAs in Input (%s files → %s)\n" \
             "${#in_cias[@]}" "$OUTPUT_DIR"
        say "  0) 취소" "  0) Cancel"
        echo
        local conv_mode
        prompt="$(msg "선택 [1]: " "Select [1]: ")"
        read -rp "$prompt" conv_mode || return
        case "$conv_mode" in
            0) say "취소했습니다." "Cancelled."; pause; return ;;
            a|A) batch_convert_input; return ;;
            ""|1) ;;
            *) say "잘못된 입력입니다." "Invalid input."; pause; return ;;
        esac
    fi

    local cia title
    title="$(msg "변환할 CIA 파일:" "CIA file to convert:")"
    cia=$(pick_file "$title" ${all_cias[@]+"${all_cias[@]}"})
    [[ -z "$cia" ]] && { say "취소했습니다." "Cancelled."; pause; return; }

    local base
    base="$(basename "${cia%.*}")"
    echo
    say "출력 3DS 이름" "Output 3DS filename"
    msgf "  · 이름만 입력        → %s/이름.3ds\n" "  · Name only          → %s/name.3ds\n" "$OUTPUT_DIR"
    msgf "  · 하위 폴더 포함     → %s/하위폴더/이름.3ds\n" "  · With subfolder     → %s/subfolder/name.3ds\n" "$OUTPUT_DIR"
    say  "  · / 또는 ~/ 로 시작  → 해당 절대/홈 경로 그대로 사용" "  · Starts with / or ~ → Use exact absolute/home path"
    local out_raw
    prompt="$(msgf "이름 [%s.3ds]: " "Name [%s.3ds]: " "$base")"
    read_line_edit "$prompt" out_raw || { say "취소했습니다." "Cancelled."; pause; return; }

    local out_3ds
    out_3ds="$(resolve_out_path "$out_raw" "3ds" "$OUTPUT_DIR" "$base")" || {
        warn "$(msg "출력 경로 생성 실패" "Failed to resolve output path")"; pause; return
    }
    if ! confirm_overwrite "$out_3ds"; then
        say "취소했습니다." "Cancelled."; pause; return
    fi

    echo
    say "[1/1] cia-unix로 CIA → 3DS 변환..." "[1/1] Converting CIA → 3DS via cia-unix..."
    if ! cia_unix_convert "$cia" "$out_3ds"; then
        warn "$(msg "cia-unix 변환 실패" "cia-unix conversion failed")"; pause; return
    fi

    echo
    msgf "변환 완료: %s (%s bytes)\n" "Conversion complete: %s (%s bytes)\n" "$out_3ds" "$(file_size "$out_3ds")"
    say "Azahar/Citra에서 바로 실행할 수 있습니다." "Ready to launch in Azahar/Citra."
    pause_with_open "$(dirname "$out_3ds")" "$(msg "출력 폴더 열기" "Open output folder")"
}

# ---------- 메뉴 4: 헤더 정보 조회 ----------
menu_inspect() {
    echo; say "=== CIA / 3DS 헤더 정보 조회 ===" "=== Inspect CIA / 3DS Header ==="; echo
    local -a roms=()
    local f existing already title prompt
    while IFS= read -r f; do [[ -n "$f" ]] && roms+=("$f"); done < <(list_rom_in "$INPUT_DIR")
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        already=0
        for existing in ${roms[@]+"${roms[@]}"}; do
            [[ "$existing" == "$f" ]] && { already=1; break; }
        done
        [[ "$already" -eq 0 ]] && roms+=("$f")
    done < <(list_rom_in "$OUTPUT_DIR")

    title="$(msg "조회할 CIA / 3DS 파일:" "CIA / 3DS file to inspect:")"
    local target
    target=$(pick_file "$title" ${roms[@]+"${roms[@]}"})
    [[ -z "$target" ]] && { say "취소했습니다." "Cancelled."; pause; return; }

    echo
    echo "──────────────────────────────────────────────────"
    msgf " 파일:     %s\n" " File:         %s\n" "$target"
    msgf " 용량:     %s bytes\n" " Size:         %s bytes\n" "$(file_size "$target")"
    if read_rom_meta "$target"; then
        msgf " Title ID: %s\n" " Title ID:     %s\n" "$ROM_TITLE_ID"
        msgf " 제품코드: %s\n" " Product Code: %s\n" "$ROM_PROD_CODE"
        msgf " 버전:     v%s.%s.%s (major=%s, minor=%s, micro=%s)\n" \
             " Version:      v%s.%s.%s (major=%s, minor=%s, micro=%s)\n" \
             "$ROM_MAJOR" "$ROM_MINOR" "$ROM_MICRO" "$ROM_MAJOR" "$ROM_MINOR" "$ROM_MICRO"
        msgf " 암호화:   %s\n" " Encryption:   %s\n" "$ROM_CRYPTO"
    else
        warn "$(msg "ctrtool로 메타데이터를 파싱하지 못했습니다." "Failed to parse metadata with ctrtool.")"
    fi
    echo "──────────────────────────────────────────────────"
    echo
    local detail_ans
    prompt="$(msg "ctrtool 전체 상세 출력을 볼까요? (y/N): " "Show full ctrtool output? (y/N): ")"
    read -rp "$prompt" detail_ans
    if is_yes "$detail_ans"; then
        echo
        "$CTR" "$target" 2>&1 | head -n 60
    fi
    pause
}

# ---------- 메뉴 5: 정리 ----------
menu_cleanup() {
    echo; say "=== 작업 파일 정리 ===" "=== Clean Up Working Files ==="; echo
    local -a targets=()
    [[ -d "$EXTRACTED_DIR" && -n "$(ls -A "$EXTRACTED_DIR" 2>/dev/null)" ]] && targets+=("Extracted ($EXTRACTED_DIR)")
    [[ -d "$WORK_DIR" ]] && targets+=("Work ($WORK_DIR)")
    local f
    for f in "$INPUT_DIR"/*-decrypted.3ds "$INPUT_DIR"/*-decrypted.cci; do
        [[ -f "$f" ]] && targets+=("$f")
    done
    if [[ "${#targets[@]}" -eq 0 ]]; then
        say "정리할 항목이 없습니다." "Nothing to clean up."
        pause; return
    fi
    say "삭제할 항목:" "Items to delete:"
    local t; for t in "${targets[@]}"; do echo "  - $t"; done
    echo
    local ans prompt
    prompt="$(msg "삭제할까요? (y/N): " "Delete these items? (y/N): ")"
    read -rp "$prompt" ans
    is_yes "$ans" || { say "취소했습니다." "Cancelled."; pause; return; }
    clean_extracted || { say "일부 항목 정리를 취소했습니다." "Cleanup partially cancelled."; pause; return; }
    clean_work
    for f in "$INPUT_DIR"/*-decrypted.3ds "$INPUT_DIR"/*-decrypted.cci; do
        [[ -f "$f" ]] && rm -f -- "$f"
    done
    say "정리 완료." "Cleanup complete."
    pause
}

# ---------- 메뉴 6: 설정 (경로 및 언어) ----------
prompt_set_dir() {
    local label="$1" current="$2"
    local raw resolved prompt
    echo >&2
    msgf "새 %s 경로를 입력하세요 (드래그 앤 드롭 및 ~ 지원, 빈칸=취소)\n" \
         "Enter new %s path (drag-and-drop and ~ supported, blank=cancel)\n" "$label" >&2
    prompt="$(msgf "경로 [%s]: " "Path [%s]: " "$current")"
    if ! read_line_edit "$prompt" raw; then
        return 1
    fi
    [[ -z "$(normalize_path "$raw")" ]] && return 1
    resolved="$(resolve_dir_path "$raw" "$SCRIPT_DIR")" || return 1
    printf '%s\n' "$resolved"
}

menu_paths() {
    local sub new_dir ans prompt lang_label
    while true; do
        clear
        lang_label="$(msg "한국어 (Korean)" "English")"
        echo "=================================================="
        say  " 작업 경로 및 언어 설정 (영구 저장)" " Paths & Language Settings (Saved Permanently)"
        echo "=================================================="
        echo
        msgf " 1. Input     (CIA 입력):   %s\n" " 1. Input     (CIA input):    %s\n" "$INPUT_DIR"
        msgf " 2. Extracted (분해 작업):  %s\n" " 2. Extracted (Extraction):   %s\n" "$EXTRACTED_DIR"
        msgf " 3. Output    (결과 출력):  %s\n" " 3. Output    (Output dir):   %s\n" "$OUTPUT_DIR"
        msgf " 4. 모든 경로 기본값(%s/...)으로 초기화\n" " 4. Reset all paths to defaults (%s/...)\n" "$SCRIPT_DIR"
        msgf " 5. 언어 변경 (Language):   %s\n" " 5. Language / 언어 변경:     %s\n" "$lang_label"
        say  " 0. 메인 메뉴로 돌아가기" " 0. Back to main menu"
        echo
        prompt="$(msg "선택: " "Select: ")"
        read -rp "$prompt" sub || return
        case "$sub" in
            1)
                if new_dir="$(prompt_set_dir "Input" "$INPUT_DIR")"; then
                    INPUT_DIR="$new_dir"
                    save_config
                    msgf "Input 경로 변경: %s\n" "Input path updated: %s\n" "$INPUT_DIR"
                    pause
                fi
                ;;
            2)
                if new_dir="$(prompt_set_dir "Extracted" "$EXTRACTED_DIR")"; then
                    validate_safe_dir "$new_dir" "Extracted"
                    EXTRACTED_DIR="$new_dir"
                    save_config
                    msgf "Extracted 경로 변경: %s\n" "Extracted path updated: %s\n" "$EXTRACTED_DIR"
                    pause
                fi
                ;;
            3)
                if new_dir="$(prompt_set_dir "Output" "$OUTPUT_DIR")"; then
                    OUTPUT_DIR="$new_dir"
                    save_config
                    msgf "Output 경로 변경: %s\n" "Output path updated: %s\n" "$OUTPUT_DIR"
                    pause
                fi
                ;;
            4)
                prompt="$(msg "기본 경로로 초기화할까요? (y/N): " "Reset paths to default? (y/N): ")"
                read -rp "$prompt" ans
                if is_yes "$ans"; then
                    INPUT_DIR="$DEFAULT_INPUT_DIR"
                    EXTRACTED_DIR="$DEFAULT_EXTRACTED_DIR"
                    OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
                    save_config
                    init_dirs
                    say "기본 경로로 초기화했습니다." "Paths reset to defaults."
                    pause
                fi
                ;;
            5)
                if [[ "$LANG_CODE" == "ko" ]]; then
                    LANG_CODE="en"
                else
                    LANG_CODE="ko"
                fi
                save_config
                say "언어가 한국어로 변경되었습니다." "Language changed to English."
                pause
                ;;
            0|q|Q)
                return
                ;;
            *)
                say "잘못된 입력입니다." "Invalid input."
                pause
                ;;
        esac
    done
}

# ---------- 메뉴 ----------
menu() {
    clear
    echo "=================================================="
    say  " 3DS CIA 분해 / 재구성 / 변환 도구 (v29)" " 3DS CIA Extract / Rebuild / Convert Tool (v29)"
    echo "=================================================="
    echo
    echo " Input:     $INPUT_DIR"
    echo " Extracted: $EXTRACTED_DIR"
    echo " Output:    $OUTPUT_DIR"
    echo " Keys:      $(detect_key_files)"
    echo
    local n_in=0 n_out=0
    n_in=$(list_cia_in "$INPUT_DIR" | wc -l | tr -d ' ')
    n_out=$(list_cia_in "$OUTPUT_DIR" | wc -l | tr -d ' ')
    msgf " Input/*.cia: %s 개    Output/*.cia: %s 개\n" \
         " Input/*.cia: %s files    Output/*.cia: %s files\n" \
         "$n_in" "$n_out"
    if [[ -d "$EXTRACTED_DIR" && -n "$(ls -A "$EXTRACTED_DIR" 2>/dev/null)" ]]; then
        local src="?"
        [[ -f "$EXTRACTED_DIR/.source_name" ]] && src="$(cat "$EXTRACTED_DIR/.source_name")"
        load_extracted_meta "$EXTRACTED_DIR"
        if [[ "$META_TITLE_ID" != "?" ]]; then
            msgf " Extracted: 편집 중 — %s (%s / v%s.%s.%s)\n" \
                 " Extracted: In progress — %s (%s / v%s.%s.%s)\n" \
                 "$src" "$META_TITLE_ID" "$META_MAJOR" "$META_MINOR" "$META_MICRO"
        else
            msgf " Extracted: 편집 중 (%s)\n" " Extracted: In progress (%s)\n" "$src"
        fi
    else
        say " Extracted: 비어 있음" " Extracted: Empty"
    fi
    [[ -d "$WORK_DIR" ]] && say " Work:      이전 실행 잔여물 있음" " Work:      Leftover files from previous run"
    echo
    say " 1. CIA 분해 (CIA → Extracted)" " 1. Extract CIA (CIA → Extracted)"
    say " 2. CIA 재구성 (Extracted → CIA)" " 2. Rebuild CIA (Extracted → CIA)"
    say " 3. CIA → 3DS 변환 (단일 / 일괄 변환)" " 3. Convert CIA → 3DS (Single / Batch)"
    say " 4. CIA / 3DS 헤더 정보 조회" " 4. Inspect CIA / 3DS Header"
    say " 5. 작업 파일 정리" " 5. Clean Up Working Files"
    say " 6. 설정 (경로 / 언어 변경)" " 6. Settings (Paths / Language)"
    say " 7. 종료" " 7. Exit"
    echo
}

main() {
    load_config
    case "${CIA_LANG:-}" in
        ko|KO) LANG_CODE="ko" ;;
        en|EN) LANG_CODE="en" ;;
    esac
    [[ -n "${CIA_INPUT_DIR:-}" ]]     && INPUT_DIR="$(resolve_dir_path "$CIA_INPUT_DIR" "$ORIG_PWD")"
    [[ -n "${CIA_EXTRACTED_DIR:-}" ]] && EXTRACTED_DIR="$(resolve_dir_path "$CIA_EXTRACTED_DIR" "$ORIG_PWD")"
    [[ -n "${CIA_OUTPUT_DIR:-}" ]]    && OUTPUT_DIR="$(resolve_dir_path "$CIA_OUTPUT_DIR" "$ORIG_PWD")"
    parse_args "$@"

    if [[ "$LANG_CODE" != "ko" && "$LANG_CODE" != "en" ]]; then
        select_initial_language
    fi

    init_dirs
    check_tools
    local choice prompt
    while true; do
        menu
        prompt="$(msg "선택: " "Select: ")"
        read -rp "$prompt" choice || { echo; say "종료합니다." "Exiting."; exit 0; }
        case "$choice" in
            1) menu_extract ;;
            2) menu_rebuild ;;
            3) menu_convert ;;
            4) menu_inspect ;;
            5) menu_cleanup ;;
            6) menu_paths ;;
            7|q|Q) say "종료합니다." "Exiting."; exit 0 ;;
            *) say "잘못된 입력입니다." "Invalid input."; pause ;;
        esac
    done
}

main "$@"