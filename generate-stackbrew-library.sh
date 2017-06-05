#!/bin/bash
set -e

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

declare -A aliases=(
	#[suite]='tag1 tag2 ...'
)
aliases[$(< latest)]+=' latest'
aliases[$(< rolling)]+=' rolling' # https://github.com/docker-library/official-images/issues/2323#issuecomment-284409446

declare -A noVersion=(
	#[suite]=1
)

develSuite="$(
	wget -qO- http://archive.ubuntu.com/ubuntu/dists/devel/Release \
		| awk -F ': ' '$1 == "Codename" { print $2; exit }' \
		|| true
)"
if [ "$develSuite" ]; then
	aliases[$develSuite]+=' devel'
fi

archMaps=( $(
	git ls-remote --heads https://github.com/tianon/docker-brew-ubuntu-core.git \
		| awk -F '[\t/]' '$4 ~ /^dist-/ { gsub(/^dist-/, "", $4); print $4 "=" $1 }'
) )
arches=()
declare -A archCommits=()
for archMap in "${archMaps[@]}"; do
	arch="${archMap%%=*}"
	commit="${archMap#${arch}=}"
	arches+=( "$arch" )
	archCommits[$arch]="$commit"
done

versions=( */ )
versions=( "${versions[@]%/}" )

cat <<-EOH
# Maintained by Tianon as proxy for upstream's official builds.

# see https://partner-images.canonical.com/core/
# see also https://wiki.ubuntu.com/Releases#Current

Maintainers: Tianon Gravi <tianon@debian.org> (@tianon)
GitRepo: https://github.com/tianon/docker-brew-ubuntu-core.git
GitCommit: $(git log --format='format:%H' -1)
EOH
for arch in "${arches[@]}"; do
	cat <<-EOA
		# https://github.com/tianon/docker-brew-ubuntu-core/tree/dist-${arch}
		${arch}-GitFetch: refs/heads/dist-${arch}
		${arch}-GitCommit: ${archCommits[$arch]}
	EOA
done

# prints "$2$1$3$1...$N"
join() {
	local sep="$1"; shift
	local out; printf -v out "${sep//%/%%}%s" "$@"
	echo "${out#$sep}"
}

for version in "${versions[@]}"; do
	# TODO serial="$(awk -F '=' '$1 == "SERIAL" { print $2; exit }' "$version/build-info.txt" 2>/dev/null || true)"
	# [ "$serial" ] || continue

	versionAliases=()

	[ -s "$version/alias" ] && versionAliases+=( $(< "$version/alias") )

	# TODO versionAliases+=( $version-$serial )

	versionAliases+=(
		$version
		${aliases[$version]}
	)

	versionArches=()
	for arch in "${arches[@]}"; do
		if wget --quiet --spider "https://github.com/tianon/docker-brew-ubuntu-core/raw/${archCommits[$arch]}/${version}/Dockerfile"; then
			versionArches+=( "$arch" )
		fi
	done

	# assert some amount of sanity
	[ "${#versionArches[@]}" -gt 0 ]

	echo
	cat <<-EOE
		Tags: $(join ', ' "${versionAliases[@]}")
		Architectures: $(join ', ' "${versionArches[@]}")
		Directory: $version
	EOE
done
