#!/bin/bash
set -e

cd "$(dirname "$BASH_SOURCE")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

for v in "${versions[@]}"; do
	serial="$(awk -F '=' '$1 == "SERIAL" { print $2; exit }' "$v/build-info.txt" 2>/dev/null || true)"
	[ "$serial" ] || serial='missing'
	echo '- `ubuntu:'"$v"'`: '"$serial"
done
