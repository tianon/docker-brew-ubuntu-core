#!/bin/bash
set -e

currentDaily='vivid'

cd "$(dirname "$BASH_SOURCE")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

for v in "${versions[@]}"; do
	(
		cd "$v"
		thisTarBase="$v-core-amd64"
		thisTar="$thisTarBase.tar.gz"
		baseUrl="http://cdimage.ubuntu.com/ubuntu-core"
		if [ "$currentDaily" != "$v" ]; then
			baseUrl="$baseUrl/$v"
		fi
		wget -qN "$baseUrl/daily/current/"{{MD5,SHA{1,256}}SUMS{,.gpg},"$thisTarBase.manifest"}
		wget -N "$baseUrl/daily/current/$thisTar"
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

# delete all the apt list files since they're big and get stale quickly
RUN rm -rf /var/lib/apt/lists/*
# this forces "apt-get update" in dependent images, which is also good

# enable the universe
RUN sed -i 's/^#\s*\(deb.*universe\)$/\1/g' /etc/apt/sources.list

# upgrade packages for now, since the tarballs aren't updated frequently enough
RUN apt-get update && apt-get dist-upgrade -y && rm -rf /var/lib/apt/lists/*

# overwrite this with 'CMD []' in a dependent Dockerfile
CMD ["/bin/bash"]
EOF
	)
done

user="$(docker info | awk '/^Username:/ { print $2 }')"
[ -z "$user" ] || user="$user/"
for v in "${versions[@]}"; do
	( set -x; docker build -t "${user}ubuntu-core:$v" "$v" )
done
