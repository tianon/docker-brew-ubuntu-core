#!/bin/bash
set -Eeuo pipefail

cd "$(dirname "$BASH_SOURCE")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

arch="$(< arch)"

toVerify=()
for v in "${versions[@]}"; do
	if ! grep -qE "^$arch\$" "$v/arches"; then
		continue
	fi

	case "$v" in
		trusty | xenial)
			thisTarBase="ubuntu-$v-core-cloudimg-$arch"
			thisTar="$thisTarBase-root.tar.gz"
			baseUrl="https://partner-images.canonical.com/core/$v/current"
			(
				cd "$v"
				wget -qN "$baseUrl/"{{MD5,SHA{1,256}}SUMS{,.gpg},"$thisTarBase.manifest",'unpacked/build-info.txt'}
				wget -N --progress=dot:giga "$baseUrl/$thisTar"
			)

			cat > "$v/Dockerfile" <<EOF
FROM scratch
ADD $thisTar /
EOF
			cat >> "$v/Dockerfile" <<'EOF'

# a few minor docker-specific tweaks
# see https://github.com/docker/docker/blob/9a9fc01af8fb5d98b8eec0740716226fadb3735c/contrib/mkimage/debootstrap
RUN set -xe \
	\
# https://github.com/docker/docker/blob/9a9fc01af8fb5d98b8eec0740716226fadb3735c/contrib/mkimage/debootstrap#L40-L48
	&& echo '#!/bin/sh' > /usr/sbin/policy-rc.d \
	&& echo 'exit 101' >> /usr/sbin/policy-rc.d \
	&& chmod +x /usr/sbin/policy-rc.d \
	\
# https://github.com/docker/docker/blob/9a9fc01af8fb5d98b8eec0740716226fadb3735c/contrib/mkimage/debootstrap#L54-L56
	&& dpkg-divert --local --rename --add /sbin/initctl \
	&& cp -a /usr/sbin/policy-rc.d /sbin/initctl \
	&& sed -i 's/^exit.*/exit 0/' /sbin/initctl \
	\
# https://github.com/docker/docker/blob/9a9fc01af8fb5d98b8eec0740716226fadb3735c/contrib/mkimage/debootstrap#L71-L78
	&& echo 'force-unsafe-io' > /etc/dpkg/dpkg.cfg.d/docker-apt-speedup \
	\
# https://github.com/docker/docker/blob/9a9fc01af8fb5d98b8eec0740716226fadb3735c/contrib/mkimage/debootstrap#L85-L105
	&& echo 'DPkg::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' > /etc/apt/apt.conf.d/docker-clean \
	&& echo 'APT::Update::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' >> /etc/apt/apt.conf.d/docker-clean \
	&& echo 'Dir::Cache::pkgcache ""; Dir::Cache::srcpkgcache "";' >> /etc/apt/apt.conf.d/docker-clean \
	\
# https://github.com/docker/docker/blob/9a9fc01af8fb5d98b8eec0740716226fadb3735c/contrib/mkimage/debootstrap#L109-L115
	&& echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/docker-no-languages \
	\
# https://github.com/docker/docker/blob/9a9fc01af8fb5d98b8eec0740716226fadb3735c/contrib/mkimage/debootstrap#L118-L130
	&& echo 'Acquire::GzipIndexes "true"; Acquire::CompressionTypes::Order:: "gz";' > /etc/apt/apt.conf.d/docker-gzip-indexes \
	\
# https://github.com/docker/docker/blob/9a9fc01af8fb5d98b8eec0740716226fadb3735c/contrib/mkimage/debootstrap#L134-L151
	&& echo 'Apt::AutoRemove::SuggestsImportant "false";' > /etc/apt/apt.conf.d/docker-autoremove-suggests
EOF

			if [ "$v" = 'xenial' ]; then
				cat >> "$v/Dockerfile" <<'EOF'

# delete all the apt list files since they're big and get stale quickly
RUN rm -rf /var/lib/apt/lists/*
# this forces "apt-get update" in dependent images, which is also good
# (see also https://bugs.launchpad.net/cloud-images/+bug/1699913)
EOF
			else
				cat >> "$v/Dockerfile" <<'EOF'

# verify that the APT lists files do not exist
RUN [ -z "$(apt-get indextargets)" ]
# (see https://bugs.launchpad.net/cloud-images/+bug/1699913)
EOF
			fi

			cat >> "$v/Dockerfile" <<'EOF'

# make systemd-detect-virt return "docker"
# See: https://github.com/systemd/systemd/blob/aa0c34279ee40bce2f9681b496922dedbadfca19/src/basic/virt.c#L434
RUN mkdir -p /run/systemd && echo 'docker' > /run/systemd/container

CMD ["/bin/bash"]
EOF
			;;

		*)
			thisTarBase="ubuntu-$v-oci-$arch-root"
			thisTar="$thisTarBase.tar.gz"
			baseUrl="https://partner-images.canonical.com/oci/$v/current"
			(
				cd "$v"
				wget -qN "$baseUrl/"{SHA256SUMS{,.gpg},"$thisTarBase.manifest",'unpacked/build-info.txt'}
				wget -N --progress=dot:giga "$baseUrl/$thisTar"
			)
			cat > "$v/Dockerfile" <<-EOF
				FROM scratch
				ADD $thisTar /
				CMD ["bash"]
			EOF
			;;
	esac

	toVerify+=( "$v" )
done

if [ "${#toVerify[@]}" -gt 0 ]; then
	( set -x; ./verify.sh "${toVerify[@]}" )
fi
