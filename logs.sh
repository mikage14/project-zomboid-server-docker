#!/usr/bin/env bash

set -o pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
service="pzserver"

compose=(
    docker compose
    --project-directory "${project_dir}"
    -f "${project_dir}/docker-compose.yml"
)

state_dir="$(mktemp -d)"
ts_file="${state_dir}/last-timestamp"

cleanup() {
    rm -rf -- "${state_dir}"
}

# EXIT alone is not enough: bash skips it when the script is killed by a
# signal, and this script normally ends with Ctrl-C.
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM HUP

# mawk reads stdin in blocks and does not even parse a record until its input
# buffer fills, so a live stream stalls for kilobytes at a time no matter how
# often the program calls fflush(). -W interactive switches it to line buffered
# reads and unbuffered writes, which is what makes follow mode usable.
awk_cmd=(awk)
if awk -W version 2>/dev/null | head -n 1 | grep -qi mawk; then
    awk_cmd=(awk -W interactive)
fi

# Reads `docker compose logs --timestamps` on stdin, drops known noise and
# prints the remaining records without the timestamp prefix.
#
# $1: file to write the timestamp of the last consumed record into (used to
#     resume exactly where we left off when the stream is interrupted).
# $2: records with a timestamp at or before this one are dropped, so resuming
#     with `--since` cannot print a line twice.
filter_logs() {
    "${awk_cmd[@]}" -v ts_file="$1" -v skip_until="$2" '
function is_known_exception(line) {
    return line ~ /AdvancedAnimator\$1\.visitFileFailed/ \
        || line ~ /DebugFileWatcher\.registerDir.*Exception thrown/ \
        || line ~ /IsoPropertyType\.lookupOrDefaultStr.*Exception thrown/
}

function is_known_single_line_noise(line) {
    return line ~ /XuiSkin\$EntityUiStyle\.(Load|LoadComponentInfo).*Could not find icon:/ \
        || line ~ /IsoSpriteManager\.AddSprite.*duplicate texture/ \
        || line ~ /BrokenFences\.addBrokenTiles.*Missing ThumpSound/ \
        || line ~ /VehicleScript\.Loaded.*extents != physicsChassisShape/ \
        || line ~ /ActionState\.parse.*Canceled loading wrong transition/ \
        || line ~ /Lua\(Vanilla\)\.doMapZones.*can.t find map objects file:/ \
        || line ~ /recursive require\(\):/ \
        || line ~ /require\(".*"\) failed/ \
        || line ~ /FluidContainerScript\.load.*Sanitizing container name/ \
        || line ~ /TaggedObjectManager\.createTagBits.*new tag discovered/ \
        || line ~ /ModelScript\.(check|ScriptsLoaded)/ \
        || line ~ /CraftRecipeComponentScript\.getIconTexture.*missing UiConfigScript/ \
        || line ~ /handleMannequinZone.*Mannequin zone missing properties/ \
        || line ~ /Missing texture: media\/textures\/weather\/fogwhite\.png/ \
        || line ~ /\[S_API FAIL\] Tried to access Steam interface/ \
        || line ~ /LOG  : Mod.*> loading / \
        || line ~ /LOG  : Mod.*> mod ".*" overrides / \
        || line ~ /Workshop: GetItemState\(\)=Installed ID=/ \
        || line ~ /Workshop: item state CheckItemState -> Ready ID=/ \
        || line ~ /Workshop: [0-9]+ installed to / \
        || line ~ /LOG  : General.*> thread [0-9]+\/[0-9]+ loading / \
        || line ~ /^\*\*\* INFO: Found (Mods|Workshop IDs) including /
}

# docker compose writes its own diagnostics to stderr, which we merge into the
# stream so real server errors are never lost. Its routine chatter is not
# interesting though.
function is_compose_chatter(line) {
    return line ~ /^time="[^"]*" level=(warning|info) msg=/
}

{
    line = $0

    # Strip the timestamp docker prepends. Lines without one come from the
    # compose CLI itself rather than from the container, and it still emits
    # terminal escapes for its status messages despite --no-color.
    if (match(line, /^[0-9][0-9-]*T[0-9][0-9:.]*Z /)) {
        ts = substr(line, 1, RLENGTH - 1)
        line = substr(line, RLENGTH + 1)
        if (skip_until != "" && ts <= skip_until) {
            next
        }
        last_ts = ts
    } else {
        gsub(/\033\[[0-9;]*[A-Za-z]/, "", line)
        gsub(/\r/, "", line)
        if (line == "") {
            next
        }
    }

    if (is_compose_chatter(line)) {
        next
    }

    # pzexe prints command-line options and their values on separate lines.
    # Never echo the admin-password option or the value immediately after it.
    if (hide_next_argument) {
        hide_next_argument = 0
        next
    }

    if (line ~ /^pzexe: arg: -adminpassword$/) {
        hide_next_argument = 1
        next
    }

    # Java stack traces are indented; the next log record starts at column 0.
    # Only indented lines are swallowed, so an unexpected record can never be
    # hidden by a stack trace we failed to recognise the end of.
    if (skipping_exception) {
        if (line ~ /^[ \t]/) {
            next
        }
        skipping_exception = 0
    }

    if (is_known_exception(line)) {
        skipping_exception = 1
        next
    }

    if (is_known_single_line_noise(line)) {
        next
    }

    print line
    fflush()
}

END {
    if (last_ts != "" && ts_file != "") {
        print last_ts > ts_file
    }
}
'
}

# -a is required: without it compose only reports containers that are running,
# so a stopped server would look like a deleted one.
container_id() {
    "${compose[@]}" ps -aq "${service}" 2>/dev/null | head -n 1
}

container_is_running() {
    local id
    id="$(container_id)"
    [[ -n "${id}" ]] && [[ "$(docker inspect -f '{{.State.Running}}' "${id}" 2>/dev/null)" == "true" ]]
}

# Honour an explicit --tail/-n from the caller, otherwise replay everything.
tail_args=(--tail=all)
for arg in "$@"; do
    case "${arg}" in
        --tail | --tail=* | -n | -n=*)
            tail_args=()
            break
            ;;
    esac
done

# A single follow stream replays the retained history and then keeps printing.
# Splitting it into "read history" plus "follow from now" would silently drop
# everything the server logged in between.
skip_until=""

while :; do
    since_args=()
    if [[ -n "${skip_until}" ]]; then
        # Resume from the last record we printed. Anything logged while we were
        # disconnected is replayed, and filter_logs drops the duplicate.
        since_args=(--since "${skip_until}")
        tail_args=(--tail=all)
    fi

    : > "${ts_file}"

    "${compose[@]}" logs --follow --timestamps --no-color --no-log-prefix \
        "${tail_args[@]}" "${since_args[@]}" "$@" "${service}" 2>&1 |
        filter_logs "${ts_file}" "${skip_until}"
    status=${PIPESTATUS[0]}

    last_ts="$(cat -- "${ts_file}" 2>/dev/null)"
    if [[ -n "${last_ts}" ]]; then
        skip_until="${last_ts}"
    fi

    # docker compose logs -f returns when the container goes away, so reattach
    # instead of exiting on every server restart.
    if container_is_running; then
        printf '=== ログの追従が切れました。再接続します… ===\n' >&2
        sleep 1
        continue
    fi

    if [[ -z "$(container_id)" ]]; then
        printf '=== サービス %s のコンテナが見つかりません (exit=%s)。終了します。 ===\n' \
            "${service}" "${status}" >&2
        exit 1
    fi

    printf '=== コンテナが停止しています。起動を待機中… ===\n' >&2
    while ! container_is_running; do
        if [[ -z "$(container_id)" ]]; then
            printf '=== コンテナが削除されました。終了します。 ===\n' >&2
            exit 1
        fi
        sleep 2
    done
    printf '=== コンテナが起動しました。ログの追従を再開します。 ===\n' >&2
done
