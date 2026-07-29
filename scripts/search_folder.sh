#!/bin/bash

# Resolves the maps listed in MAP_IDS to folders inside the downloaded Workshop mods,
# copies them into the server's media/maps folder and writes the resulting list to
# maps.txt for entry.sh to put into the Map= setting.
#
# The list is built by walking MAP_IDS, not by walking the file system, so the order
# given in MAP_IDS is preserved. That order decides how the maps are layered, and a
# map found twice (Build 42 mods ship the same map under both "common" and a version
# folder) would otherwise end up in Map= twice.
#
# Mod layouts:
#   Build 41: <workshop id>/mods/<mod>/media/maps/<map>
#   Build 42: <workshop id>/mods/<mod>/{common,42,42.x}/media/maps/<map>
search_folder() {
    local search_dir="$1"
    local map_ids="$2"
    local map_dir="${HOMEDIR}/pz-dedicated/media/maps"
    local out="${HOMEDIR}/maps.txt"
    local candidates=()
    local map_ids_array=()
    local layers=() versions=()
    local map_id candidate build entry

    mkdir -p "$map_dir"
    : > "$out"

    # Collect every map folder once, then match the names against MAP_IDS below.
    mapfile -t candidates < <(find "$search_dir" -type d -path "*/mods/*/media/maps/*" \
        -not -path "*/media/maps/*/*" 2>/dev/null | sort -V)
    echo "*** INFO: Found ${#candidates[@]} map folder(s) under ${search_dir} ***"

    IFS=";" read -ra map_ids_array <<< "$map_ids"
    for map_id in "${map_ids_array[@]}"; do
        [ -n "$map_id" ] || continue

        # A Build 42 mod can ship the same map in "common" and in one or more version
        # folders, and the game stacks them in that order. Collect every layer that
        # provides this map so they can be copied in the same order.
        layers=()
        versions=()
        for candidate in "${candidates[@]}"; do
            [ "${candidate##*/}" == "$map_id" ] || continue
            build="${candidate%/media/maps/*}"
            build="${build##*/}"
            case "$build" in
                common) layers+=("$candidate") ;;
                *) versions+=("${build}|${candidate}") ;;
            esac
        done
        if [ ${#versions[@]} -gt 0 ]; then
            # Sort on the build folder alone; sorting whole paths compares "42/" against
            # "42.13/" and gets the order wrong.
            while IFS= read -r entry; do
                layers+=("${entry#*|}")
            done < <(printf '%s\n' "${versions[@]}" | sort -t'|' -k1,1V)
        fi

        if [ ${#layers[@]} -eq 0 ]; then
            echo "*** WARN: Map '${map_id}' was not found in any installed mod, skipping ***"
            continue
        fi

        if [ ! -d "$map_dir/$map_id" ]; then
            mkdir -p "$map_dir/$map_id"
            for candidate in "${layers[@]}"; do
                echo "*** INFO: Copying map '${map_id}' from ${candidate} ***"
                cp -r "$candidate/." "$map_dir/$map_id/"
            done
        fi

        printf '%s;' "$map_id" >> "$out"
    done
}

parent_folder="$1"

if [ ! -d "$parent_folder" ]; then
    exit 1
fi

# Call the search_folder function with the provided arguments
search_folder "$parent_folder" "$2"
