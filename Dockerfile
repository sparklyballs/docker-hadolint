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
	&& git checkout "${HADOLINT_COMMIT}"
	
FROM alpine:${ALPINE_VER} as packages-stage

############## packages stage ##############

# install build packages
RUN \
	apk add --no-cache \
		cabal \
		ghc \
		git \
		musl-dev \
		wget

FROM  packages-stage as build-stage

############## build stage ##############

# add artifacts from source stage
COPY --from=fetch-stage /source /source

# set workdir
WORKDIR /source/hadolint

RUN \
	set -ex \
	&& cabal update \
	&& cabal configure \
	&& cabal build \
	&& cabal install \
	&& mkdir -p \
		/build \
	&& cp /root/.cabal/bin//hadolint /build/

FROM alpine:${ALPINE_VER} as compress-stage

############## compress stage ##############

# add artifacts from fetch and strip stages
COPY --from=build-stage /build /build

# install compress packages
RUN \
	apk add --no-cache \
		upx

# compress hadolint
RUN \
	set -ex \
	&& upx  \
		--best \
		--ultra-brute \
	/build/hadolint


FROM alpine:${ALPINE_VER}

############## runtime stage ##############

# add artifacts from compress stage
COPY --from=compress-stage /build/hadolint /bin/

CMD ["/bin/hadolint", "-"]
