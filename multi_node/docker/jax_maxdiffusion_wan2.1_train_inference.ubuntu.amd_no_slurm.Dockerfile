# CONTEXT {'gpu_vendor': 'AMD', 'guest_os': 'UBUNTU'}
###############################################################################
#
# MIT License
#
# Copyright (c) Advanced Micro Devices, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
#################################################################################

ARG BASE_DOCKER=rocm/pyt-megatron-lm-jax-nightly-private:jax_rocm7.1_jax_0.7.1_20251215
FROM $BASE_DOCKER
USER root
ENV WORKSPACE_DIR=/workspace
RUN mkdir -p $WORKSPACE_DIR
WORKDIR $WORKSPACE_DIR

# Environment variables
ENV HIP_FORCE_DEV_KERNARG=1
ARG MAX_JOBS_ARG=192
ENV MAX_JOBS=${MAX_JOBS_ARG}

# Argument to check current GPU arch
ARG MAD_SYSTEM_GPU_ARCHITECTURE
ENV HIP_ARCHITECTURES=${MAD_SYSTEM_GPU_ARCHITECTURE}
RUN echo HIP_ARCHITECTURES = ${HIP_ARCHITECTURES}

# Install necessary system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    openssh-client \
    rsync \
    iproute2 \
    net-tools \
    iputils-ping && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    python3 -m pip install --upgrade pip && \
    pip install "huggingface_hub[cli]"

RUN pip install \
    scikit-image \
    torch==2.8.0 \
    torchvision==0.24.0 \
    torchcodec \
    imageio-ffmpeg \
    --break-system-packages --find-links https://repo.radeon.com/rocm/manylinux/rocm-rel-7.0/
    
RUN pip install \
    flax==0.11.2 \
    tokamax \
    einshape \
    typeguard==2.13.3 \
    qwix==0.1.5 --no-deps

# Libraries for IB fabric
RUN apt-get update && apt-get install -y \
    libelf-dev \
    unzip \
    gcc \
    make \
    libtool \
    autoconf \
    librdmacm-dev \
    rdmacm-utils \
    infiniband-diags \
    ibverbs-utils \
    perftest \
    ethtool \
    libibverbs-dev \
    rdma-core \
    strace \
    libibmad5 \
    libibnetdisc5 \
    ibverbs-providers \
    libibumad-dev \
    libibumad3 \
    libibverbs1 \
    libnl-3-dev \
    libnl-route-3-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR $WORKSPACE_DIR/

# NOTE: Broadcom RDMA drivers will be mounted from the host at runtime
# This ensures the container uses the exact same driver version as the host
# Host driver locations that will be mounted:
#   - /usr/local/lib/libbnxt_re*.so      -> Container /usr/local/lib/
#   - /etc/libibverbs.d/bnxt_re.driver   -> Container /etc/libibverbs.d/
#   - /etc/bnxt_re/bnxt_re.conf          -> Container /etc/bnxt_re/
#
# Host driver version detected during setup:
#   /usr/local/lib/libbnxt_re-rdmav34.so (362K, dated Nov 18 18:04)

# Create directories for driver mounting
RUN mkdir -p /etc/libibverbs.d /etc/bnxt_re

# Configure ldconfig to include /usr/local/lib
RUN echo /usr/local/lib >> /etc/ld.so.conf && ldconfig

# Note: ibv_devices will work only at runtime when host devices and drivers are mounted

# Display installed packages for verification
RUN pip list

WORKDIR /app

# Create necessary directories
RUN mkdir -p /app/hf_home /app/.cache/miopen /app/.cache/jax /app/output

# Set up environment for runtime
ENV HF_HOME=/app/hf_home
ENV MIOPEN_CUSTOM_CACHE_DIR=/app/.cache/miopen
ENV JAX_COMPILATION_CACHE_DIR=/app/.cache/jax
