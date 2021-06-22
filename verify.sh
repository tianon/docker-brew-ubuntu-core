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
	trap "gpgconf --kill all || :; rm -rf '$GNUPGHOME'" EXIT
	gpg --keyserver keyserver.ubuntu.com --recv-keys "$gpgFingerprint"
fi

hostArch="$(dpkg --print-architecture)"
arch="$(cat arch 2>/dev/null || true)"
: ${arch:=$hostArch}

for v in "${versions[@]}"; do
	case "$v" in
		trusty | xenial)
			thisTarBase="ubuntu-$v-core-cloudimg-$arch"
			thisTar="$thisTarBase-root.tar.gz"
			sumTypes=( sha256 sha1 md5 )
			;;

		*)
			thisTarBase="ubuntu-$v-oci-$arch"
			thisTar="$thisTarBase-root.tar.gz"
			sumTypes=( sha256 )
			;;
	esac
	for sums in "${sumTypes[@]}"; do
		sumsFile="$v/${sums^^}SUMS" # "SHA256SUMS"
		sumCmd="${sums}sum" # "sha256sum"
		if [ -n "$gpgFingerprint" ]; then
			if [ ! -f "$sumsFile.gpg" ]; then
				echo >&2 "warning: '$sumsFile.gpg' appears to be missing!"
				badness=1
			else
				( set -x; gpg --batch --verify "$sumsFile.gpg" "$sumsFile" )
			fi
		fi
		if [ -s "$sumsFile" ]; then
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
