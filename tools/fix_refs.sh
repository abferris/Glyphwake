#!/usr/bin/env bash
# Rewrites every stale res:// reference to a moved file: for each basename given, finds the
# file's current location on disk and rewrites any reference whose res:// path ends in that
# basename but points somewhere else.
#
#   Usage: tools/fix_refs.sh <Basename.cs> [more basenames...]
#
# Covers .tscn, .tres, .gd, .cs and .import files, plus .gdshader and .cfg for the
# post-check. Excludes .godot/ (auto-rebuilt, never hand-edit) and docs/ (the tree and
# catalogue are updated by hand; past/ worklogs are kept as written). Prints one line per
# file actually changed, then a count.
#
# Why: moving a file on disk changes its res:// path and silently breaks every reference --
# a scene loads without the script, a resource without its class -- with no error at
# runtime. Moving inside the Godot editor's FileSystem dock rewrites references
# automatically; on-disk moves need this. The .uid sidecar must travel with its own .cs:
# the reference fixes assume identity survived, and a missing .uid means Godot mints a new
# one for the uid-based references that point at the file.
#
# The project tree is walked once up front and indexed in memory. A per-basename find/grep
# walk costs ~7s on /mnt/c (DrvFs is I/O bound), which made a 38-file reorg take minutes.

cd "$(dirname "$0")/.." || exit 1

# basename -> space-free index into locations, built in one walk.
declare -A locations
while IFS= read -r -d '' f; do
    locations["./${f##*/}"]="$f"
done < <(find . -name '*.cs' -not -path './.godot/*' -not -path './docs/*' -print0)

# Every file that could hold a reference. -print0 keeps paths with spaces intact.
mapfile -d '' candidates < <(find . \
    \( -name '*.tscn' -o -name '*.tres' -o -name '*.gd' -o -name '*.cs' \
       -o -name '*.import' -o -name '*.gdshader' -o -name '*.cfg' \) \
    -not -path './.godot/*' -not -path './docs/*' -print0)

changed=0
for name in "$@"; do
    # Reconstruct the on-disk hits from the index: a basename maps to several paths when
    # duplicates exist, so scan the index rather than trusting a single lookup.
    matches=()
    for key in "${!locations[@]}"; do
        if [ "${key#./}" = "$name" ]; then matches+=("${locations[$key]}"); fi
    done
    if [ "${#matches[@]}" -eq 0 ]; then
        echo "SKIP   $name (not found on disk)"
        continue
    fi
    if [ "${#matches[@]}" -gt 1 ]; then
        echo "WARN   $name found in ${#matches[@]} places, using the first -- check the others:"
        printf '         %s\n' "${matches[@]}"
    fi
    new=${matches[0]}
    newres="res://${new#./}"
    # Escape every ERE metacharacter. Escaping only a partial set makes '+' quantify the
    # preceding char, so a basename like MyTool+X.cs silently fails to match itself and
    # instead matches MyToolX.cs -- rewriting an unrelated file's reference.
    esc=$(printf '%s' "$name" | sed 's/[][\\.^$*+?(){}|]/\\&/g')
    case "$new" in
        *.cs)
            if [ ! -f "$new.uid" ]; then
                echo "WARN   $new has no $name.uid alongside it -- Godot will mint a fresh"
                echo "       UID and uid= references to this script will break"
            fi
            ;;
    esac

    for f in "${candidates[@]}"; do
        grep -qE "res://[^\"]*/${esc}" "$f" 2>/dev/null || continue
        before=$(md5sum "$f" | cut -d' ' -f1)
        sed -i -E "s|res://[^\"]*/${esc}|${newres}|g" "$f"
        after=$(md5sum "$f" | cut -d' ' -f1)
        if [ "$before" != "$after" ]; then
            echo "FIXED  $f -> $newres"
            changed=$((changed+1))
        fi
    done

    # Anything still pointing at this basename from a path other than its new home is a
    # reference the rewrite did not reach (a file type outside the rewrite set, or a
    # quoted/embedded form the pattern missed).
    stale=$(grep -rhoE "res://[^\"]*/${esc}" "${candidates[@]}" 2>/dev/null \
        | grep -vxF "$newres" | sort -u)
    if [ -n "$stale" ]; then
        echo "WARN   $name is still referenced somewhere other than $newres:"
        printf '         %s\n' $stale
    fi
done
echo "----"
echo "$changed file(s) rewritten"
