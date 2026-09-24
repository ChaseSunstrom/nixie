# A dated copy of NIXIE_COPY_FROM in NIXIE_COPY_TO, hard-linked to the last
# one so unchanged files take no space, keeping NIXIE_COPY_KEEP of them. A
# copy that did not finish stays a .partial and is never the one linked to.
set -euo pipefail
src=$NIXIE_COPY_FROM
dst=$NIXIE_COPY_TO
keep=$NIXIE_COPY_KEEP
mkdir -p "$dst"
stamp=$(date -u +%Y-%m-%dT%H%M%SZ)
last=$(find "$dst" -mindepth 1 -maxdepth 1 -type d -name '20*' | sort | tail -1)
rm -rf "$dst"/.partial-*
rsync -a --delete ${last:+--link-dest="$last"} "$src/" "$dst/.partial-$stamp/"
mv "$dst/.partial-$stamp" "$dst/$stamp"
find "$dst" -mindepth 1 -maxdepth 1 -type d -name '20*' | sort | head -n -"$keep" | xargs -r rm -rf
echo "copied $src to $dst/$stamp"
