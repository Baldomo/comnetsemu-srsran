FROM ubuntu:bionic as base

# Install dependencies
RUN apt-get -qy update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -qqy \
        cmake \
        libuhd-dev \
        uhd-host \
        libboost-program-options-dev \
        libvolk1-dev \
        libfftw3-dev \
        libmbedtls-dev \
        libsctp-dev \
        libconfig++-dev \
        curl \
        iputils-ping \
        iproute2 \
        iptables \
        unzip && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /srslte

# Pinned git commit used for this example
ARG COMMIT=c353480769a57607a228ecc75f6a750fa3730907

# Download and build
RUN curl -LO https://github.com/jgiovatto/srsLTE/archive/${COMMIT}.zip && \
    unzip ${COMMIT}.zip && \
    rm ${COMMIT}.zip

WORKDIR /srslte/srsLTE-${COMMIT}/build

RUN cmake .. && \
    make -j4 && \
    make install

# Update dynamic linker
RUN ldconfig

WORKDIR /srslte

# Copy all .example files and remove that suffix
RUN cp srsLTE-${COMMIT}/*/*.example ./ && \
    bash -c 'for file in *.example; do mv "$file" "${file%.example}"; done'

# Run commands with line buffered standard output
# (-> get log messages in real time)
ENTRYPOINT [ "stdbuf", "-o", "L" ]
