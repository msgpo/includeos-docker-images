FROM ubuntu:xenial as base

RUN apt-get update && apt-get -y install \
    sudo \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Add fixuid to change permissions for bind-mounts. Set uid to same as host with -u <uid>:<guid>
RUN addgroup --gid 1000 docker && \
    adduser --uid 1000 --ingroup docker --home /home/docker --shell /bin/sh --disabled-password --gecos "" docker && \
    usermod -aG sudo docker && \
    sed -i.bkp -e \
      's/%sudo\s\+ALL=(ALL\(:ALL\)\?)\s\+ALL/%sudo ALL=NOPASSWD:ALL/g' \
      /etc/sudoers
RUN USER=docker && \
    GROUP=docker && \
    curl -SsL https://github.com/boxboat/fixuid/releases/download/v0.3/fixuid-0.3-linux-amd64.tar.gz | tar -C /usr/local/bin -xzf - && \
    chown root:root /usr/local/bin/fixuid && \
    chmod 4755 /usr/local/bin/fixuid && \
    mkdir -p /etc/fixuid && \
    printf "user: $USER\ngroup: $GROUP\n" > /etc/fixuid/config.yml

# TAG can be specified when building with --build-arg TAG=..., this is redeclared in the source-build stage
ARG TAG=v0.12.0-rc.3
ENV TAG=$TAG
LABEL dockerfile.version=01 \
      includeos.version=$TAG
WORKDIR /service

#########################
FROM base as source-build

RUN apt-get update && apt-get -y install \
    git \
    lsb-release \
    net-tools \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Triggers new build if there are changes to head
ADD https://api.github.com/repos/hioa-cs/IncludeOS/git/refs/heads/dev version.json

RUN echo "cloning $TAG"

RUN cd ~ && pwd && \
  git clone https://github.com/hioa-cs/IncludeOS.git && \
  cd IncludeOS && \
  git checkout $TAG && \
  git submodule update --init --recursive && \
  git fetch --tags

RUN cd ~ && pwd && \
  cd IncludeOS && \
  ./install.sh -n

###########################
FROM base as build

RUN apt-get update && apt-get -y install \
    clang-5.0 \
    cmake \
    nasm \
    python-pip \
    && rm -rf /var/lib/apt/lists/* \
    && pip install pystache antlr4-python2-runtime && \
    apt-get remove -y python-pip && \
    apt autoremove -y

COPY --from=source-build /usr/local/includeos /usr/local/includeos/
COPY --from=source-build /root/IncludeOS/etc/install_dependencies_linux.sh /
COPY entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]

CMD mkdir -p build && \
  cd build && \
  cp $(find /usr/local/includeos -name chainloader) /service/build/chainloader && \
  cmake .. && \
  make

#############################
FROM base as grubify

RUN apt-get update && apt-get -y install \
  dosfstools \
  grub-pc

COPY --from=source-build /usr/local/includeos/scripts/grubify.sh /home/ubuntu/IncludeOS_install/includeos/scripts/grubify.sh

ENTRYPOINT ["fixuid", "/home/ubuntu/IncludeOS_install/includeos/scripts/grubify.sh"]
