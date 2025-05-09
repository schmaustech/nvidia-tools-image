#!/bin/bash
# Set working dir
cd /root

# Set tool versions 
MLNXTOOLVER=23.07-1.el9
MFTTOOLVER=4.30.0-139
MLXUPVER=4.30.0

# Set architecture
ARCH=`uname -m`

# Pull mlnx-tools from EPEL
wget https://dl.fedoraproject.org/pub/epel/9/Everything/$ARCH/Packages/m/mlnx-tools-$MLNXTOOLVER.noarch.rpm

# Arm architecture fixup for mft-tools
if [ "$ARCH" == "aarch64" ]; then export ARCH="arm64"; fi

# Pull mft-tools
wget https://www.mellanox.com/downloads/MFT/mft-$MFTTOOLVER-$ARCH-rpm.tgz

# Install mlnx-tools into container
dnf install mlnx-tools-$MLNXTOOLVER.noarch.rpm -y

# Install kernel-devel package supplied in container
rpm -ivh /root/rpms/kernel-*.rpm --nodeps
mkdir /lib/modules/$(uname -r)/
ln -s /usr/src/kernels/$(uname -r) /lib/modules/$(uname -r)/build

# Install mft-tools into container
tar -xzf mft-$MFTTOOLVER-$ARCH-rpm.tgz 
cd /root/mft-$MFTTOOLVER-$ARCH-rpm
#./install.sh --without-kernel
./install.sh 

# Change back to root workdir
cd /root

# x86 fixup for mlxup binary
if [ "$ARCH" == "x86_64" ]; then export ARCH="x64"; fi

# Pull and place mlxup binary
wget https://www.mellanox.com/downloads/firmware/mlxup/$MLXUPVER/SFX/linux_$ARCH/mlxup
mv mlxup /usr/local/bin
chmod +x /usr/local/bin/mlxup

# Set working dir
cd /root

# Set architecture
ARCH=`uname -m`

# Configure and install cuda-toolkit
dnf config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/rhel9/$ARCH/cuda-rhel9.repo
dnf clean all
dnf -y install cuda-toolkit-12-8

# Export CUDA library paths
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
export LIBRARY_PATH=/usr/local/cuda/lib64:$LIBRARY_PATH

# Git clone perftest repository
git clone https://github.com/linux-rdma/perftest.git

# Change into perftest directory
cd /root/perftest

# Build perftest with the cuda libraries included
./autogen.sh
./configure CUDA_H_PATH=/usr/local/cuda/include/cuda.h
make -j
make install

# Sleep container indefinitly
sleep infinity & wait
