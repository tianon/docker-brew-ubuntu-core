#!/bin/bash
set -e

cd "$(dirname "$BASH_SOURCE")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

arch="$(cat arch 2>/dev/null || true)"
: ${arch:=$(dpkg --print-architecture)}
for v in "${versions[@]}"; do
	(
		cd "$v"
		thisTarBase="ubuntu-$v-core-cloudimg-$arch"
		thisTar="$thisTarBase-root.tar.gz"
		baseUrl="https://partner-images.canonical.com/core/$v"
		if \
			wget -q --spider "$baseUrl/current" \
			&& wget -q --spider "$baseUrl/current/$thisTar" \
		; then
			baseUrl+='/current'
		else
			# must be xenial, lols (no "current" symlink)
			# also sometimes we don't get all the tarballs we expect
			# (so we get to try more than one of these directories)
			toAttempt=( $(wget -qO- "$baseUrl/" | awk -F '</?a[^>]*>' '$2 ~ /^[0-9.]+\/$/ { gsub(/\/$/, "", $2); print $2 }' | sort -rn) )
			current=
			for attempt in "${toAttempt[@]}"; do
				if wget -q --spider "$baseUrl/$attempt/$thisTar"; then
					current="$attempt"
					break
				fi
			done
			if [ -z "$current" ]; then
				echo >&2 "warning: cannot find 'current' for $v"
				echo >&2 "  (checked all dirs under $baseUrl/)"
				continue
			fi
			baseUrl+="/$current"
			echo "SERIAL=$current" > build-info.txt
		fi
		wget -qN "$baseUrl/"{{MD5,SHA{1,256}}SUMS{,.gpg},"$thisTarBase.manifest",'unpacked/build-info.txt'} || true
		wget -N "$baseUrl/$thisTar"
		if [ -f SHA256SUMS ]; then
			sha256sum="$(sha256sum "$thisTar" | cut -d' ' -f1)"
			if ! grep -q "$sha256sum" SHA256SUMS; then
				echo >&2 "error: '$thisTar' has invalid SHA256"
				exit 1
			fi
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

repo="$(cat repo 2>/dev/null || true)"
if [ -z "$repo" ]; then
	user="$(docker info | awk -F ': ' '$1 == "Username" { print $2; exit }')"
	repo="${user:+$user/}ubuntu-core"
fi
latest="$(< latest)"
for v in "${versions[@]}"; do
	if [ ! -f "$v/Dockerfile" ]; then
		echo >&2 "warning: $v/Dockerfile does not exist; skipping $v"
		continue
	fi
	( set -x; docker build -t "$repo:$v" "$v" )
	serial="$(awk -F '=' '$1 == "SERIAL" { print $2; exit }' "$v/build-info.txt")"
	if [ "$serial" ]; then
		( set -x; docker tag -f "$repo:$v" "$repo:$v-$serial" )
	fi
	if [ -s "$v/alias" ]; then
		for a in $(< "$v/alias"); do
			( set -x; docker tag -f "$repo:$v" "$repo:$a" )
		done
	fi
	if [ "$v" = "$latest" ]; then
		( set -x; docker tag -f "$repo:$v" "$repo:latest" )
	fi
done
