FROM ubuntu:bionic

# Install dependencies
RUN apt-get -qy update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -qqy \
        cmake \
        libzmq3-dev libczmq-dev \
        libboost-program-options-dev \
        libvolk1-dev \
        libfftw3-dev \
        libmbedtls-dev \
        libsctp-dev \
        libconfig++-dev \
        curl \
        net-tools \
        telnet \
        iperf \
        iperf3\
        iputils-ping \
        iproute2 \
        iptables \
        unzip && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /srsran

# Pinned git commit used for this example (release 21.10)
ARG COMMIT=5275f33360f1b3f1ee8d1c4d9ae951ac7c4ecd4e

# Download and build
RUN curl -LO https://github.com/srsran/srsRAN/archive/${COMMIT}.zip && \
    unzip ${COMMIT}.zip && \
    rm ${COMMIT}.zip

WORKDIR /srsran/srsRAN-${COMMIT}/build

RUN cmake -DENABLE_ZEROMQ=ON -DENABLE_UHD=OFF -DENABLE_BLADERF=OFF -DENABLE_SOAPYSDR=OFF .. && \
    make -j$(nproc --ignore=2) && \
    make install

# Update dynamic linker
RUN ldconfig

WORKDIR /srsran

# Copy all .example files and remove that suffix
# RUN cp srsRAN-${COMMIT}/*/*.example ./ && \
#     bash -c 'for file in *.example; do mv "$file" "${file%.example}"; done'

# Run commands with line buffered standard output
# (-> get log messages in real time)
# ENTRYPOINT [ "stdbuf", "-oL" ]
