#!/bin/bash
set -e

cd "$(dirname "$BASH_SOURCE")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
	versions=( "${versions[@]%/}" )
fi

for v in "${versions[@]}"; do
	(
		cd "$v"
		thisTar="ubuntu-core-$v-core-amd64.tar.gz"
		wget -qN "http://cdimage.ubuntu.com/ubuntu-core/releases/$v/release/"{MD5,SHA{1,256}}SUMS{,.gpg}
		wget -N "http://cdimage.ubuntu.com/ubuntu-core/releases/$v/release/$thisTar"
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
RUN echo '#!/bin/sh' > /usr/sbin/policy-rc.d \
	&& echo 'exit 101' >> /usr/sbin/policy-rc.d \
	&& chmod +x /usr/sbin/policy-rc.d \
	&& dpkg-divert --local --rename --add /sbin/initctl \
	&& ln -sf /bin/true /sbin/initctl \
	\
	&& echo 'force-unsafe-io' > /etc/dpkg/dpkg.cfg.d/02apt-speedup \
	\
	&& echo 'DPkg::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' > /etc/apt/apt.conf.d/no-cache \
	&& echo 'APT::Update::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' >> /etc/apt/apt.conf.d/no-cache \
	&& echo 'Dir::Cache::pkgcache ""; Dir::Cache::srcpkgcache "";' >> /etc/apt/apt.conf.d/no-cache \
	\
	&& echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/no-languages

# enable the universe ?
RUN sed -i 's/^#\s*\(deb.*universe\)$/\1/g' /etc/apt/sources.list

# heartbleed!
RUN apt-get update && apt-get install -y $(dpkg-query -W '*ssl*' | awk '{ print $1 }')
EOF
	)
done

user="$(docker info | awk '/^Username:/ { print $2 }')"
[ -z "$user" ] || user="$user/"
for v in "${versions[@]}"; do
	( set -x; docker build -t "${user}ubuntu-core:$v" "$v" )
done
