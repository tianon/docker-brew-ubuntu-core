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

develSuite="$(wget -qO- http://archive.ubuntu.com/ubuntu/dists/devel/Release | awk -F ': ' '$1 == "Codename" { print $2; exit }' || true)"
if [ "$develSuite" ]; then
	aliases[$develSuite]+=' devel'
fi

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

cat <<-EOH
# Maintained by Tianon as proxy for upstream's offical builds.

Maintainers: Tianon Gravi <tianon@debian.org> (@tianon)
GitRepo: https://github.com/tianon/docker-brew-ubuntu-core.git
GitFetch: refs/heads/dist

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

# prints "$2$1$3$1...$N"
join() {
	local sep="$1"; shift
	local out; printf -v out "${sep//%/%%}%s" "$@"
	echo "${out#$sep}"
}

systemArch="$(dpkg --print-architecture)"
for task in "${tasks[@]}"; do
	version=$(echo $task | cut -d / -f 1)
	arch=$(echo $task | cut -d / -f 2)

	tarball="$version/$arch/ubuntu-$version-core-cloudimg-$arch-root.tar.gz"
	commit="$(git log -1 --format='format:%H' -- "$version/$arch")"

	serial="$(awk -F '=' '$1 == "SERIAL" { print $2; exit }' "$version/build-info.txt" 2>/dev/null || true)"
	[ "$serial" ] || continue

	versionAliases=()

	[ -s "$version/alias" ] && versionAliases+=( $(< "$version/alias") )

	if [ -z "${noVersion[$version]}" ]; then
		fullVersion="$(git show "$commit:$tarball" | tar -xvz etc/debian_version --to-stdout 2>/dev/null || true)"
		if [ -z "$fullVersion" ] || [[ "$fullVersion" == */sid ]]; then
			fullVersion="$(eval "$(git show "$commit:$tarball" | tar -xvz etc/os-release --to-stdout 2>/dev/null || true)" && echo "$VERSION" | cut -d' ' -f1)"
		fi
		if [ "$fullVersion" ]; then
			#versionAliases+=( $fullVersion )
			if [ "${fullVersion%.*.*}" != "$fullVersion" ]; then
				# three part version like "12.04.4"
				#versionAliases+=( ${fullVersion%.*} )
				versionAliases=( $fullVersion "${versionAliases[@]}" )
			fi
		fi
	fi
	versionAliases+=( $version-$serial $version ${aliases[$version]} )

	archedVersionAliases=()
	for a in ${versionAliases[@]}; do
		archedVersionAliases+=( $(echo $a | sed 's,^\([^-]\+\)-,\1-'$arch'-,; s,^\([^-]\+\)$,\1-'$arch',') )
	done
	if [ "$arch" == "$systemArch" ]; then
		versionAliases+=( ${archedVersionAliases[@]} )
	else
		versionAliases=( ${archedVersionAliases[@]} )
	fi

	echo
	cat <<-EOE
		# $serial
		Tags: $(join ', ' "${versionAliases[@]}")
		GitCommit: $commit
		Directory: $version/$arch
	EOE
done
