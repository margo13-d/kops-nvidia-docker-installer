#!/bin/bash

set -o errexit
set -o pipefail
set -u

set -x
NVIDIA_DRIVER_VERSION="${NVIDIA_DRIVER_VERSION:-418.67}"
NVIDIA_DRIVER_DOWNLOAD_URL_DEFAULT="https://us.download.nvidia.com/tesla/${NVIDIA_DRIVER_VERSION}/NVIDIA-Linux-x86_64-${NVIDIA_DRIVER_VERSION}.run"
NVIDIA_DRIVER_DOWNLOAD_URL="${NVIDIA_DRIVER_DOWNLOAD_URL:-$NVIDIA_DRIVER_DOWNLOAD_URL_DEFAULT}"
NVIDIA_INSTALLER_RUNFILE="$(basename "${NVIDIA_DRIVER_DOWNLOAD_URL}")"
NVIDIA_INSTALL_DIR="${NVIDIA_INSTALL_DIR:-/tmp}"
INSTALLED_DOCKER_VERSION="$(apt-cache show docker-ce | grep Version | egrep -o '[0-9]{2}\.[0-9]{2}\.[0-9]')"
set -x


RETCODE_SUCCESS=0
RETCODE_ERROR=1
RETRY_COUNT=5


download_kernel_src() {
  echo "Downloading kernel sources..."
  apt-get update
  apt-get install -y linux-headers-$(uname -r)
  apt-get install -y gcc libc-dev
  echo "Downloading kernel sources... DONE."
}

download_nvidia_installer() {
  echo "Downloading Nvidia installer..."
  pushd "${NVIDIA_INSTALL_DIR}"
  curl -L -S -f "${NVIDIA_DRIVER_DOWNLOAD_URL}" -o "${NVIDIA_INSTALLER_RUNFILE}"
  popd
  echo "Downloading Nvidia installer... DONE."
}

run_nvidia_installer() {
  echo "Running Nvidia installer..."
  pushd "${NVIDIA_INSTALL_DIR}"
  sh "${NVIDIA_INSTALLER_RUNFILE}" \
    --no-install-compat32-libs \
    --log-file-name="${NVIDIA_INSTALL_DIR}/nvidia-installer.log" \
    --no-drm \
    --silent \
    --accept-license
  popd
  echo "Running Nvidia installer... DONE."
}

configure_gpu() {
  nvidia-smi -pm 1
  nvidia-smi -acp 0
  nvidia-smi --auto-boost-default=0
  nvidia-smi --auto-boost-permission=0
  nvidia-smi -ac 2505,875
}

verify_nvidia_installation() {
  echo "Verifying Nvidia installation..."
  nvidia-smi
  nvidia-modprobe -c0 -u
  echo "Verifying Nvidia installation... DONE."
}

install_nvidia_docker2() {
  curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
  distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
  curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list
  apt-get update
  NEWEST_COMPATIBLE_NVIDIA_DOCKER="$(apt-cache madison nvidia-docker2 | egrep -o "[0-9\.]+\+docker${INSTALLED_DOCKER_VERSION}-[0-9]+" | head -n1)"
  NEWEST_COMPATIBLE_NVIDIA_CONTAINER_RUNTIME="$(apt-cache madison nvidia-container-runtime | egrep -o "[0-9\.]+\+docker${INSTALLED_DOCKER_VERSION}-[0-9]+" | head -n1)"
  apt-get install -y nvidia-docker2=$NEWEST_COMPATIBLE_NVIDIA_DOCKER nvidia-container-runtime=$NEWEST_COMPATIBLE_NVIDIA_CONTAINER_RUNTIME
}

set_nvidia_container_runtime() {
  cat > /etc/docker/daemon.json <<EOL
{
    "default-runtime": "nvidia",
    "runtimes": {
        "nvidia": {
            "path": "/usr/bin/nvidia-container-runtime",
            "runtimeArgs": []
        }
    }
}
EOL
}

main() {
  download_kernel_src
  download_nvidia_installer
  run_nvidia_installer
  configure_gpu
  verify_nvidia_installation
  install_nvidia_docker2
  set_nvidia_container_runtime
}

main "$@"
