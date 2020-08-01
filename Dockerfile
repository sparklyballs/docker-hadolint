ARG UBUNTU_VER="bionic"
ARG ALPINE_VER="edge"
FROM alpine:${ALPINE_VER} as fetch-stage

############## fetch stage ##############

# install fetch packages
RUN \
	apk add --no-cache \
		bash \
		curl \
		git \
		xz 

# set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# fetch version file
RUN \
	set -ex \
	&& curl -o \
	/tmp/version.txt -L \
	"https://raw.githubusercontent.com/sparklyballs/versioning/master/version.txt"

# set workdir
WORKDIR /source/hadolint

# fetch source code
# hadolint ignore=SC1091
RUN \
	. /tmp/version.txt \
	&& set -ex \
	&& git clone "https://github.com/hadolint/hadolint" /source/hadolint \
	&& git checkout "${HADOLINT_COMMIT}" \
	&& mkdir -p \
		/opt/upx \
	&& curl -o \
	/tmp/upx.tar.gz -L \
	"https://github.com/upx/upx/releases/download/v${UPX_RELEASE}/upx-${UPX_RELEASE}-amd64_linux.tar.xz" \
	&& tar xf \
	/tmp/upx.tar.gz -C \
	/opt/upx --strip-components=1  
	

FROM ubuntu:${UBUNTU_VER} as packages-stage

############## packages stage ##############

# install build packages
RUN \
	apt-get update \
	&& apt-get install -y \
		--no-install-recommends \
		build-essential \
		ca-certificates \
		curl \
		git \
		libffi-dev \
		libgmp-dev \
		netbase \
		zlib1g-dev \
	&& curl -o \
	/tmp/haskell.sh -L \
		"https://get.haskellstack.org" \
	&& /bin/sh /tmp/haskell.sh \
	\
# cleanup
	\
	&& rm -rf \
		/tmp/* \
		/var/lib/apt/lists/* \
		/var/tmp/*

FROM  packages-stage as build-stage

############## build stage ##############

# add artifacts from source stage
COPY --from=fetch-stage /source /source

# set workdir
WORKDIR /source/hadolint

RUN \
	set -ex \
	&& stack \
		--install-ghc test \
		--no-terminal \
		--only-dependencies

RUN \
	set -ex \
	&& scripts/fetch_version.sh \
	&& stack install \
		--flag hadolint:static \
		--ghc-options="-fPIC" \
	&& mkdir -p \
		/build \
	&& cp /root/.local/bin/hadolint /build/

FROM ubuntu:${UBUNTU_VER} as compress-stage

############## compress stage ##############

# add artifacts from fetch and strip stages
COPY --from=build-stage /build /build
COPY --from=fetch-stage /opt/upx /opt/upx

# set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# compress hadolint
RUN \
	set -ex \
	&& /opt/upx/upx  \
		--best \
		--ultra-brute \
	/build/hadolint


FROM alpine:${ALPINE_VER}

############## runtime stage ##############

# add artifacts from compress stage
COPY --from=compress-stage /build/hadolint /bin/

CMD ["/bin/hadolint", "-"]
