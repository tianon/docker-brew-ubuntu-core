#!/bin/bash
set -e

cd "$(dirname "$BASH_SOURCE")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

arch="$(dpkg --print-architecture)"
for v in "${versions[@]}"; do
	(
		cd "$v/$arch"
		thisTarBase="ubuntu-$v-core-cloudimg-$arch"
		thisTar="$thisTarBase-root.tar.gz"
		baseUrl="https://partner-images.canonical.com/core/$v/current"
		wget -cqN "$baseUrl/"{{MD5,SHA{1,256}}SUMS{,.gpg},"$thisTarBase.manifest",'unpacked/build-info.txt'}
		wget -cN "$baseUrl/$thisTar"
		sha256sum="$(sha256sum "$thisTar" | cut -d' ' -f1)"
		if ! grep -q "$sha256sum" SHA256SUMS; then
			echo >&2 "error: '$thisTar' has invalid SHA256"
			exit 1
		fi
		cat > Dockerfile <<EOF
FROM scratch
ADD $thisTar /
EOF
		
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
done

user="$(docker info | awk '/^Username:/ { print $2 }')"
[ -z "$user" ] || user="$user/"
for v in "${versions[@]}"; do
	( set -x; docker build -t "${user}ubuntu-core:$v" "$v/$arch" )
done
