#!/bin/bash
set -e

declare -A aliases
aliases=(
	[trusty]='latest'
)
declare -A noVersion
noVersion=(
)

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

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

versions=( */ )
versions=( "${versions[@]%/}" )

tasks=()
for v in "${versions[@]}"; do
	arches=( $v/*/ )
	arches=( "${arches[@]%/}" )
	arches=( "${arches[@]#$v/}" )
	for arch in "${arches[@]}"; do
		dir="$(readlink -f "$v/$arch")"

		skip="$(get_part "$dir" skip '')"
		if [ -n "$skip" ]; then
			echo "Skipping $v/$arch, reason: $skip"
			continue;
		fi

		tasks+=( $v/$arch )
	done
done

url='git://github.com/vicamo/docker-brew-ubuntu-core'

cat <<-'EOH'
# maintainer: You-Sheng Yang <vicamo@gmail.com> (@vicamo)
# proxy for upstream's official builds
# see https://partner-images.canonical.com/core/

# see also https://wiki.ubuntu.com/Releases#Current
EOH

commitRange='master..dist'
commitCount="$(git rev-list "$commitRange" --count 2>/dev/null || true)"
if [ "$commitCount" ] && [ "$commitCount" -gt 0 ]; then
	echo
	echo '# commits:' "($commitRange)"
	git log --format=format:'- %h %s%n%w(0,2,2)%b' "$commitRange" | sed 's/^/#  /'
fi

systemArch="$(dpkg --print-architecture)"
for task in "${tasks[@]}"; do
	version=$(echo $task | cut -d / -f 1)
	arch=$(echo $task | cut -d / -f 2)

	commit="$(git log -1 --format='format:%H' -- "$version/$arch")"
	serial="$(awk -F '=' '$1 == "SERIAL" { print $2 }' "$version/build-info.txt")"
	
	versionAliases=()
	if [ -z "${noVersion[$version]}" ]; then
		tarball="$version/$arch/ubuntu-$version-core-cloudimg-$arch-root.tar.gz"
		fullVersion="$(tar -xvf "$tarball" etc/debian_version --to-stdout 2>/dev/null)"
		if [ -z "$fullVersion" ] || [[ "$fullVersion" == */sid ]]; then
			fullVersion="$(eval "$(tar -xvf "$tarball" etc/os-release --to-stdout 2>/dev/null)" && echo "$VERSION" | cut -d' ' -f1)"
		fi
		if [ "$fullVersion" ]; then
			versionAliases+=( $fullVersion-$arch )
			if [ "$arch" == "$systemArch" ]; then
				versionAliases+=( $fullVersion )
			fi
			if [ "${fullVersion%.*.*}" != "$fullVersion" ]; then
				# three part version like "12.04.4"
				versionAliases+=( ${fullVersion%.*}-$arch )
				if [ "$arch" == "$systemArch" ]; then
					versionAliases+=( ${fullVersion%.*} )
				fi
			fi
		fi
	fi
	versionAliases+=( $version-$arch-$serial $version-$arch )
	if [ "$arch" == "$systemArch" ]; then
		versionAliases+=( $version-$serial $version )
	fi
	if [ "x${aliases[$version]}" != "x" ]; then
		versionAliases+=( ${aliases[$version]}-$arch )
		if [ "$arch" == "$systemArch" ]; then
			versionAliases+=( ${aliases[$version]} )
		fi
	fi
	
	echo
	echo "# $serial"
	for va in "${versionAliases[@]}"; do
		echo "$va: ${url}@${commit} $version"
	done
done
