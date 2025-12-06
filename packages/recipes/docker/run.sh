#!/usr/bin/env bash
set -euo pipefail

# Run script for Docker recipe
# This spins up an Ubuntu 24.04 container with SSH on port 2222
# and host networking, mapping the current user's home directory.

# Create a temporary directory for the build context
BUILD_CONTEXT="$(mktemp -d)"
trap 'rm -rf "${BUILD_CONTEXT}"' EXIT

# Gather host user info to match in container
USER_ID=$(id -u)
GROUP_ID=$(id -g)
USER_NAME=$(whoami)

IMAGE_NAME="servobox-ubuntu-2404-dev"
CONTAINER_NAME="servobox-dev-2404"

# Write Dockerfile to the build context
# Using a unique delimiter to avoid conflicts with the wrapper script's heredoc
cat > "${BUILD_CONTEXT}/Dockerfile" << 'DOCKER_BUILD_EOF'
FROM ubuntu:24.04

ARG USER_ID=1000
ARG GROUP_ID=1000
ARG USER_NAME=servobox-usr

ENV DEBIAN_FRONTEND=noninteractive

# Install common tools and ssh server
RUN apt-get update && apt-get install -y \
    openssh-server \
    sudo \
    curl \
    wget \
    git \
    vim \
    locales \
    net-tools \
    iputils-ping \
    tmux \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Set up locale
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Configure SSH to listen on 2222
RUN sed -i 's/#Port 22/Port 2222/' /etc/ssh/sshd_config && \
    mkdir /var/run/sshd

# Remove default ubuntu user to avoid uid conflicts if we map to 1000
RUN userdel -r ubuntu || true

# Create user matching host uid/gid
RUN groupadd -g ${GROUP_ID} ${USER_NAME} || groupmod -g ${GROUP_ID} ${USER_NAME} || true
RUN useradd -m -u ${USER_ID} -g ${GROUP_ID} -s /bin/bash ${USER_NAME}
RUN echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
RUN echo "${USER_NAME}:servobox" | chpasswd

CMD ["/usr/sbin/sshd", "-D", "-e"]
DOCKER_BUILD_EOF

echo "Building Docker image ${IMAGE_NAME}..."
docker build \
    --build-arg USER_ID="${USER_ID}" \
    --build-arg GROUP_ID="${GROUP_ID}" \
    --build-arg USER_NAME="${USER_NAME}" \
    -t "${IMAGE_NAME}" \
    "${BUILD_CONTEXT}"

echo ""
echo "Starting container ${CONTAINER_NAME}..."
echo " - SSH Port: 2222 (Host)"
echo " - Network: Host"
echo " - Home: ${HOME} (Mounted)"
echo " - User: ${USER_NAME}"
echo " - Password: servobox (if keys not configured)"
echo ""

# Remove existing container if it exists (stopped or running)
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Removing existing container..."
    docker rm -f "${CONTAINER_NAME}"
fi

# Run the container
# --net=host: Shares host networking stack (all ports accessible)
docker run -it --rm \
    --net=host \
    --name "${CONTAINER_NAME}" \
    -v "${HOME}:${HOME}" \
    -v "/etc/timezone:/etc/timezone:ro" \
    -v "/etc/localtime:/etc/localtime:ro" \
    -w "${HOME}" \
    "${IMAGE_NAME}"
