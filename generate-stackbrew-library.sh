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

versions=( */ )
versions=( "${versions[@]%/}" )
url='git://github.com/tianon/docker-brew-ubuntu-core'

echo '# maintainer: Tianon Gravi <admwiggin@gmail.com> (@tianon)'

for version in "${versions[@]}"; do
	commit="$(git log -1 --format='format:%H' "$version")"
	versionAliases=()
	if [ -z "${noVersion[$version]}" ]; then
		fullVersion="$(tar -xvf "$version/${version}-core-amd64.tar.gz" etc/debian_version --to-stdout 2>/dev/null)"
		if [ -z "$fullVersion" ] || [[ "$fullVersion" == */sid ]]; then
			fullVersion="$(eval "$(tar -xvf "$version/${version}-core-amd64.tar.gz" etc/os-release --to-stdout 2>/dev/null)" && echo "$VERSION" | cut -d' ' -f1)"
			versionAliases+=( $fullVersion )
			if [ "${fullVersion%.*.*}" != "$fullVersion" ]; then
				# three part version like "12.04.4"
				versionAliases+=( ${fullVersion%.*} )
			fi
		fi
	fi
	versionAliases+=( $version ${aliases[$version]} )
	
	echo
	for va in "${versionAliases[@]}"; do
		echo "$va: ${url}@${commit} $version"
	done
done
