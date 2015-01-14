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

user="$(docker info | awk '/^Username:/ { print $2 }')"
[ -z "$user" ] || user="$user/"

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
		dir="$(readlink -f "$v/$arch")"

		skip="$(get_part "$dir" skip '')"
		if [ -n "$skip" ]; then
			echo "Skipping $v/$arch, reason: $skip"
			continue;
		fi

		tasks+=( $v/$arch )
	done
done

systemArch="$(dpkg --print-architecture)"

get_qemu_arch() {
	local arch="$1"

	if [ "$arch" = "$systemArch" ]; then
		return 0
	fi

	case "$systemArch-$arch" in
		amd64-i386|arm-armel|armel-arm|arm-armhf|armhf-arm|armel-armhf|armhf-armel|i386-amd64|powerpc-ppc64|ppc64-powerpc|sparc-sparc64|sparc64-sparc|s390-s390x|s390x-s390)
			return 0
			;;
	esac

	qemuArch=""
	case "$arch" in
		alpha|arm|armeb|i386|m68k|mips|mipsel|ppc64|sh4|sh4eb|sparc|sparc64|s390x)
			qemuArch="$arch"
			;;
		amd64)
			qemuArch="x86_64"
			;;
		armel|armhf)
			qemuArch="arm"
			;;
		arm64)
			qemuArch="aarch64"
			;;
		lpia)
			qemuArch="i386"
			;;
		powerpc|powerpcspe)
			qemuArch="ppc"
			;;
		*)
			echo >&2 "Sorry, I don't know how to support arch $arch"
			exit 1
			;;
	esac

	echo $qemuArch
	return 0
}

for task in "${tasks[@]}"; do
	v=$(echo $task | cut -d / -f 1)
	arch=$(echo $task | cut -d / -f 2)

	baseUrl="https://partner-images.canonical.com/core/$v/current"
	(
		cd "$v"
		wget -cqN "$baseUrl/"{{MD5,SHA{1,256}}SUMS{,.gpg},'unpacked/build-info.txt'}
	)

	(
		cd "$v/$arch"
		thisTarBase="ubuntu-$v-core-cloudimg-$arch"
		thisTar="$thisTarBase-root.tar.gz"
		wget -cN "$baseUrl/"{"$thisTar","$thisTarBase.manifest"}
		sha256sum="$(sha256sum "$thisTar" | cut -d' ' -f1)"
		if ! grep -q "$sha256sum" ../SHA256SUMS; then
			echo >&2 "error: '$thisTar' has invalid SHA256"
			exit 1
		fi
		cat > Dockerfile <<EOF
FROM scratch
ADD $thisTar /
EOF

		qemuArch="$(get_qemu_arch $arch)"
		if [ "x$qemuArch" != "x" ]; then
			qemuUserBin="$(which qemu-$qemuArch-static 2>&1)"
			if [ -z "$qemuUserBin" ]; then
				echo >&2 "Sorry, couldn't find binary qemu-$qemuArch-static"
				exit 1
			fi
			cp $qemuUserBin .
			cat >> Dockerfile <<EOF
ADD $(basename $qemuUserBin) $qemuUserBin
EOF
		fi

		cat >> Dockerfile <<'EOF'

# a few minor docker-specific tweaks
# see https://github.com/docker/docker/blob/master/contrib/mkimage/debootstrap
RUN echo '#!/bin/sh' > /usr/sbin/policy-rc.d \
	&& echo 'exit 101' >> /usr/sbin/policy-rc.d \
	&& chmod +x /usr/sbin/policy-rc.d \
	\
	&& dpkg-divert --local --rename --add /sbin/initctl \
	&& cp -a /usr/sbin/policy-rc.d /sbin/initctl \
	&& sed -i 's/^exit.*/exit 0/' /sbin/initctl \
	\
	&& echo 'force-unsafe-io' > /etc/dpkg/dpkg.cfg.d/docker-apt-speedup \
	\
	&& echo 'DPkg::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' > /etc/apt/apt.conf.d/docker-clean \
	&& echo 'APT::Update::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' >> /etc/apt/apt.conf.d/docker-clean \
	&& echo 'Dir::Cache::pkgcache ""; Dir::Cache::srcpkgcache "";' >> /etc/apt/apt.conf.d/docker-clean \
	\
	&& echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/docker-no-languages \
	\
	&& echo 'Acquire::GzipIndexes "true"; Acquire::CompressionTypes::Order:: "gz";' > /etc/apt/apt.conf.d/docker-gzip-indexes

# enable the universe
RUN sed -i 's/^#\s*\(deb.*universe\)$/\1/g' /etc/apt/sources.list

# overwrite this with 'CMD []' in a dependent Dockerfile
CMD ["/bin/bash"]
EOF
	)

	(
		set -x
		docker build -t "${user}ubuntu-core:$v-$arch" "$v/$arch"
		if [ "$arch" == "$systemArch" ]; then
			docker tag -f "${user}ubuntu-core:$v-$arch" "${user}ubuntu-core:$v"
		fi
	)
done
