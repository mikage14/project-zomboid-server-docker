#!/usr/bin/env bash

set -o pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

compose=(
    docker compose
    --project-directory "${project_dir}"
    -f "${project_dir}/docker-compose.yml"
)

filter_logs() {
    awk '
function is_log_header(line) {
    return line ~ /^(\[[^]]+\] )?(LOG  :|WARN :|ERROR:|DEBUG:|TRACE:)/
}

# These messages start multi-line Java exceptions. Their stack traces are
# skipped until the next structured Zomboid log record.
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

{
    # pzexe prints command-line options and their values on separate lines.
    # Never echo the admin-password option or the value immediately after it.
    if (hide_next_argument) {
        hide_next_argument = 0
        next
    }

    if ($0 ~ /^pzexe: arg: -adminpassword$/) {
        hide_next_argument = 1
        next
    }

    if (skipping_exception) {
        if (!is_log_header($0)) {
            next
        }
        skipping_exception = 0
    }

    if (is_known_exception($0)) {
        skipping_exception = 1
        next
    }

    if (is_known_single_line_noise($0)) {
        next
    }

    print
    fflush()
}
'
}

# Follow mode does not reliably replay all retained history in this environment.
# Read existing logs to EOF, then follow only lines emitted after attaching.
"${compose[@]}" logs --no-color --no-log-prefix "$@" pzserver 2>&1 |
    filter_logs

"${compose[@]}" logs -f --no-color --no-log-prefix "$@" --tail=0 pzserver 2>&1 |
    filter_logs
