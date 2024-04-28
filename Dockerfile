ARG ALPINE_VER="edge"
FROM alpine:${ALPINE_VER} as fetch-stage

############## fetch stage ##############

# build args
ARG RELEASE
ARG GMP_RELEASE

# install fetch packages
RUN \
	apk add --no-cache \
		bash \
		curl \
		jq \
		lzip \
		tar

# set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# fetch source
RUN \
	set -ex \
	&& if [ -z ${RELEASE+x} ]; then \
	RELEASE=$(curl -u "${SECRETUSER}:${SECRETPASS}" -sX GET "https://api.github.com/repos/hadolint/hadolint/commits/master" \
	| jq -r ".sha"); \
	fi \
	&& RELEASE="${RELEASE:0:7}" \
	&& mkdir -p \
		/src/hadolint \
	&& curl -o \
	/tmp/hadolint.tar.gz -L \
		"https://github.com/hadolint/hadolint/archive/${RELEASE}.tar.gz" \
	&& tar xf \
	/tmp/hadolint.tar.gz -C \
	/src/hadolint --strip-components=1

RUN \
	mkdir -p \
		/src/gmp \
	&& curl -o \
	/tmp/gmp.tar.lz -L \
		"https://gmplib.org/download/gmp/gmp-${GMP_RELEASE}.tar.lz" \
	&& tar xf \
	/tmp/gmp.tar.lz -C \
	/src/gmp --strip-components=1


FROM alpine:${ALPINE_VER} as packages-stage

############## packages stage ##############

# install build packages
RUN \
	apk add --no-cache \
		autoconf \
		automake \
		cabal \
		ghc \
		git \
		libffi-dev \
		libtool \
		m4 \
		musl-dev \
		texinfo \
		wget

FROM  packages-stage as build-stage

############## build stage ##############

# add artifacts from source stage
COPY --from=fetch-stage /src /src

# build gmp
WORKDIR /src/gmp
RUN apk add --no-cache \
	g++ \
	make

RUN \
	./configure \
		--build=$CBUILD \
		--host=$CHOST \
		--with-sysroot=$CBUILDROOT \
		--prefix=/usr \
		--infodir=/usr/share/info \
		--mandir=/usr/share/man \
		--localstatedir=/var/state/gmp \
		--enable-cxx \
		--with-pic \
	&& make \
	&& make install

# set workdir
WORKDIR /src/hadolint

RUN \
	set -ex \
	&& cabal update \
	&& cabal configure \
	&& cabal build \
	&& cabal install \
	&& mkdir -p \
		/build \
	&& cp /root/.local/bin/hadolint /build/

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


FROM scratch

############## runtime stage ##############

# add artifacts from compress stage
COPY --from=compress-stage --chmod=777 /build/hadolint /bin/hadolint

CMD ["/bin/hadolint", "-"]
