#!/bin/bash
set -e

cd "$(dirname "$BASH_SOURCE")"

get_part() {
	local dir="$1"
	shift
	local part="$1"
	shift
	if [ -f "$dir/$part" ]; then
		cat "$dir/$part"
		return 0
	fi
	if [ -f "$part" ]; then
		cat "$part"
		return 0
	fi
	if [ $# -gt 0 ]; then
		echo "$1"
		return 0
	fi
	return 1
}

args=( "$@" )
if [ ${#args[@]} -eq 0 ]; then
	args=( */ )
fi

versions=()
for arg in "${args[@]}"; do
	arg=${arg%/}
	arch=$(echo $arg | cut -d / -f 2)
	v=$(echo $arg | cut -d / -f 1)
	if [ "$arch" == "$v" ]; then
		arch=
	fi

	if [ -z "`echo ${versions[@]} | grep $v`" ]; then
		versions+=( $v )
	fi

	name=arches_$v
	if [ "$arch" ]; then
		eval arches=\( \${${name}[@]} \)
		if [ ${#arches[@]} -ne 0 ]; then
			if [ -z "`echo ${arches[@]} | grep $arch`" ]; then
				eval $name+=\( "$arch" \)
			fi
		else
			eval $name=\( "$arch" \)
		fi
	else
		arches=( $v/*/ )
		arches=( "${arches[@]%/}" )
		arches=( "${arches[@]#$v/}" )
		if [ ${#arches[@]} -lt 0 -o "${arches[0]}" != "*" ]; then
			eval $name=\( ${arches[@]} \)
		fi
	fi

	#echo "arch: $arch, v: $v"
	#echo "versions: ${versions[@]}"
	#eval echo "$name: \${${name}[@]}"
	#echo
done

tasks=()
for v in "${versions[@]}"; do
	name=arches_$v
	eval arches=\( \${${name}[@]} \)
	for arch in "${arches[@]}"; do
		tasks+=( $v/$arch )
	done
done

for task in "${tasks[@]}"; do
	v=$(echo $task | cut -d / -f 1)
	arch=$(echo $task | cut -d / -f 2)

	skip="$(get_part "$task" skip '')"
	if [ -n "$skip" ]; then
		echo "Skipping $v/$arch, reason: $skip"
		continue;
	fi

	(
		cd "$v"
		thisTarBase="ubuntu-$v-core-cloudimg-$arch"
		baseUrl="https://partner-images.canonical.com/core/$v/current"
		echo
		wget -qO- "$baseUrl/unpacked/build-info.txt" | git --no-pager diff --no-index -- "build-info.txt" - || true
		wget -qO- "$baseUrl/$thisTarBase.manifest" | git --no-pager diff --no-index -- "$arch/$thisTarBase.manifest" - || true
		echo
	)
done
