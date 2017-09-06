#!/bin/bash
set -Eeuo pipefail

cd "$(dirname "$BASH_SOURCE")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

badness=

gpgFingerprint="$(grep -v '^#' gpg-fingerprint 2>/dev/null || true)"
if [ -z "$gpgFingerprint" ]; then
	echo >&2 'warning: missing gpg-fingerprint! skipping PGP verification!'
	badness=1
else
	export GNUPGHOME="$(mktemp -d)"
	trap "rm -r '$GNUPGHOME'" EXIT
	gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$gpgFingerprint"
fi

hostArch="$(dpkg --print-architecture)"
arch="$(cat arch 2>/dev/null || true)"
: ${arch:=$hostArch}

for v in "${versions[@]}"; do
	thisTarBase="ubuntu-$v-core-cloudimg-$arch"
	thisTar="$thisTarBase-root.tar.gz"
	baseUrl="https://partner-images.canonical.com/core/$v"
	for sums in sha256 sha1 md5; do
		sumsFile="$v/${sums^^}SUMS" # "SHA256SUMS"
		sumCmd="${sums}sum" # "sha256sum"
		if [ "$gpgFingerprint" ]; then
			if [ ! -f "$sumsFile.gpg" ]; then
				echo >&2 "warning: '$sumsFile.gpg' appears to be missing!"
				badness=1
			else
				( set -x; gpg --batch --verify "$sumsFile.gpg" "$sumsFile" )
			fi
		fi
		if [ -f "$sumsFile" ]; then
			grep " *$thisTar\$" "$sumsFile" | ( set -x; cd "$v" && "$sumCmd" -c - )
		else
			echo >&2 "warning: missing '$sumsFile'!"
			badness=1
		fi
	done
done

if [ "$badness" ]; then
	false
fi
