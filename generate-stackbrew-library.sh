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

cat <<-'EOH'
# maintainer: Tianon Gravi <tianon@debian.org> (@tianon)
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

arch="$(dpkg --print-architecture)"
for version in "${versions[@]}"; do
	commit="$(git log -1 --format='format:%H' -- "$version")"
	serial="$(awk -F '=' '$1 == "SERIAL" { print $2 }' "$version/build-info.txt")"
	
	versionAliases=()
	if [ -z "${noVersion[$version]}" ]; then
		tarball="$version/ubuntu-$version-core-cloudimg-$arch-root.tar.gz"
		fullVersion="$(tar -xvf "$tarball" etc/debian_version --to-stdout 2>/dev/null)"
		if [ -z "$fullVersion" ] || [[ "$fullVersion" == */sid ]]; then
			fullVersion="$(eval "$(tar -xvf "$tarball" etc/os-release --to-stdout 2>/dev/null)" && echo "$VERSION" | cut -d' ' -f1)"
		fi
		if [ "$fullVersion" ]; then
			versionAliases+=( $fullVersion )
			if [ "${fullVersion%.*.*}" != "$fullVersion" ]; then
				# three part version like "12.04.4"
				versionAliases+=( ${fullVersion%.*} )
			fi
		fi
	fi
	versionAliases+=( $version-$serial $version ${aliases[$version]} )
	
	echo
	echo "# $serial"
	for va in "${versionAliases[@]}"; do
		echo "$va: ${url}@${commit} $version"
	done
done
