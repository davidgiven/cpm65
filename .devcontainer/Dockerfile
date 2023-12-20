FROM mcr.microsoft.com/vscode/devcontainers/base:ubuntu-22.04

# To prevent interactive shells
ENV DEBIAN_FRONTEND=noninteractive

# hadolint ignore=DL3008,DL3009
RUN apt-get update && \
  apt-get install -y --no-install-recommends \
  curl \
  locales \
  locales-all \
  sudo \
  tzdata \
  wget && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

# Set the locale
ENV LC_ALL en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8

# Set timezone inside Docker container
ENV TZ=UTC
RUN echo $TZ >/etc/timezone && \
  rm /etc/localtime && \
  dpkg-reconfigure -f noninteractive tzdata

# Install needed buildenvironment
RUN mkdir -p /tmp/install
COPY ./install/install.sh /tmp/install/install.sh
COPY ./install/requirements.txt /tmp/install/requirements.txt
RUN cd /tmp/install && \
  bash install.sh && \
  rm -rf /tmp/install
