# Containerization NVIDIA Tools for RMDA Environments

Containerization of the NVIDIA Tools for use in RDMA environments.

**Goal**: The goal of this document is to make the NVIDIA MFT Tooling along with Perftest and CUDA libraries containerized to allow for various RDMA testing functionality.

## NVIDIA MFT Tooling, Mlnx Tools and Mlxup

The MFT package is a set of firmware management tools used to:

* Generate a standard or customized NVIDIA firmware image querying for firmware information
* Burn a firmware image
* Make configuration changes to the firmware settings

The following is a list of the available tools in MFT, together with a brief description of what each tool performs. 

| **Component**   | **Description/Function**                                                                                                                             |
|-----------------|------------------------------------------------------------------------------------------------------------------------------------------------------|
| mst             | Starts/stops the register access driver Lists the available mst devices                                                                              |
| mlxburn         | Generation of a standard or customized NVIDIA firmware image for burning (.bin or .mlx)to the Flash/EEPROM attached to a NVIDIA HCA or switch device |
| flint           | This tool burns/query a firmware binary image or an expansion ROM image to the Flash device of a NVIDIA network adapter/gateway/switch device        |
| debug utilities | A set of debug utilities (e.g., itrace, fwtrace, mlxtrace, mlxdump, mstdump, mlxmcg, wqdump, mcra, mlxi2c, i2c, mget_temp, and pckt_drop)            |
| mlxup           | The utility enables discovery of available NVIDIA adapters and indicates whether firmware update is required for each adapter                        |
| mlnx-tools      | Mellanox userland tools and scripts                                                                                                                  |

Sources:
[Mlnx-tools Repo](https://github.com/Mellanox/mlnx-tools)
[MFT Tools](https://network.nvidia.com/products/adapter-software/firmware-tools/)
[Mlxup](https://network.nvidia.com/support/firmware/mlxup-mft/)

## Perftest Tooling

In addition to the MFT tools this container contains testing tooling for validating RDMA connectivity and performance when used in conjunction with NVIDIA Network Operator and NVIDIA GPU Operator.  Specifically the ability to use the `ib_write_bw` command with the `--use_cuda` switch to demonstrate RDMA from one GPU in a node to another GPU in another node in an OpenShift cluster.  The `ib_write_bw` command is part of the perftest suite which is a collection of tests written over uverbs intended for use as a performance micro-benchmark. The tests may be used for HW or SW tuning as well as for functional testing.

The collection contains a set of bandwidth and latency benchmark such as:

* Send        - ib_send_bw and ib_send_lat
* RDMA Read   - ib_read_bw and ib_read_lat
* RDMA Write  - ib_write_bw and ib_write_lat
* RDMA Atomic - ib_atomic_bw and ib_atomic_lat
* Native Ethernet (when working with MOFED2) - raw_ethernet_bw, raw_ethernet_lat

## Workflow Sections

- [Prerequisites](#prerequisites)
- [Building The Container](#building-the-container)
- [Running The Container](#running-the-container)
- [What The Container Can Do](#what-the-container-can-do)

## Building The Container

The first step is to make a nvidia-tools directory.

~~~bash
$ mkdir -p ~/nvidia-tools
$ cd nvidia-tools
~~~

~~~bash
$ cat <<EOF > dockerfile.tools 
# Start from UBI9 image
FROM registry.access.redhat.com/ubi9/ubi:latest

# Set work directory
WORKDIR /root

# Copy in packages not available in UBI repo
COPY show_gids /usr/bin/show_gids
COPY ibdev2netdev /usr/sbin/ibdev2netdev
#RUN dnf install /root/rpms/usbutils*.rpm -y

# DNF install packages either from repo or locally
RUN dnf install wget procps-ng pciutils yum jq iputils ethtool net-tools kmod systemd-udev rpm-build gcc make git autoconf automake libtool -y
RUN dnf install fio usbutils infiniband-diags libglvnd-opengl libibumad librdmacm libxcb libxcb-devel libxkbcommon libxkbcommon-x11 pciutils-devel rdma-core-devel xcb-util xcb-util-image xcb-util-keysyms xcb-util-renderutil xcb-util-wm -y

# Cleanup 
RUN dnf clean all

# Run container entrypoint
COPY entrypoint.sh /root/entrypoint.sh
RUN chmod +x /root/entrypoint.sh

ENTRYPOINT ["/root/entrypoint.sh"]
~~~

~~~bash
cat entrypoint.sh 
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
~~~

~~~bash
$ podman build . -f dockerfile.tools -t quay.io/redhat_emp1/ecosys-nvidia/nvidia-tools:0.0.1
STEP 1/10: FROM registry.access.redhat.com/ubi9/ubi:latest
STEP 2/10: WORKDIR /root
--> Using cache 05ab94448a150a327f9d8b573e4f84dea1b92343b04625732ff95d2245d883d3
--> 05ab94448a15
STEP 3/10: COPY show_gids /usr/bin/show_gids
--> Using cache c311a8020674b1b165b5695be0ce32ded986b4b741b5d52bbf575aab050ea04a
--> c311a8020674
STEP 4/10: COPY ibdev2netdev /usr/sbin/ibdev2netdev
--> Using cache df91b2f89cad5c498646cc609d3762a19069217026f370fa72f5d56e5d28142c
--> df91b2f89cad
STEP 5/10: RUN dnf install wget procps-ng pciutils yum jq iputils ethtool net-tools kmod systemd-udev rpm-build gcc make git autoconf automake libtool -y
--> Using cache c2e169180778bf7b17bf168e587f51a45206b6b16c921425a695c920953daea6
--> c2e169180778
STEP 6/10: RUN dnf install fio usbutils infiniband-diags libglvnd-opengl libibumad librdmacm libxcb libxcb-devel libxkbcommon libxkbcommon-x11 pciutils-devel rdma-core-devel xcb-util xcb-util-image xcb-util-keysyms xcb-util-renderutil xcb-util-wm -y
--> Using cache 42c1747917d6b0f1fcee46b787abd35b03c88c41d59c52c3d85207c138406db9
--> 42c1747917d6
STEP 7/10: RUN dnf clean all
--> Using cache 4010d3345bd58dc01d62bf514676b8e3b59b30ff317398f47e050eb9658e71dc
--> 4010d3345bd5
STEP 8/10: COPY entrypoint.sh /root/entrypoint.sh
--> Using cache 31fe23b60402b637579ff3dc5bc919947a2f0e96b5d504f96cb872fc21d6b7e1
--> 31fe23b60402
STEP 9/10: RUN chmod +x /root/entrypoint.sh
--> Using cache 2cf01c7cf3708db4889258e21eee1dd94ebdfe2256ceb56b064a914b6fd496be
--> 2cf01c7cf370
STEP 10/10: ENTRYPOINT ["/root/entrypoint.sh"]
--> Using cache 25013c77ed2a16b2741c596a3ef7a6c47f9a84752b513d0a3a5d51bfb5f79ca7
COMMIT quay.io/redhat_emp1/ecosys-nvidia/nvidia-tools:0.0.1
--> 25013c77ed2a
Successfully tagged quay.io/redhat_emp1/ecosys-nvidia/nvidia-tools:0.0.1
25013c77ed2a16b2741c596a3ef7a6c47f9a84752b513d0a3a5d51bfb5f79ca7
~~~

## Running The Container

The container will need to run priviledged so we can access the hardware devices.  To do this we will create a `ServiceAccount` and `Namespace` for it to run in.

~~~bash
$ cat <<EOF > nvidiatools-project.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: nvidiatools
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nvidiatools
  namespace: nvidiatools
EOF
~~~

Once the resource file is generated create it on the cluster.

~~~bash
$ oc create -f nvidiatools-project.yaml 
namespace/nvidiatools created
serviceaccount/nvidiatoolscreated
~~~

Now that the project has been created assign the appropriate privileges to the service account.

~~~bash
$ oc -n nvidiatools adm policy add-scc-to-user privileged -z mfttool
clusterrole.rbac.authorization.k8s.io/system:openshift:scc:privileged added: "nvidiatools"
~~~

Depending on what we want to do with the NVIDIA tools we might create one or two pods, the latter for doing RDMA testing between nodes.  I normally put a nodeSelector into the pod yaml to make sure it will run on the node where I want it to run.  This could probably be done with anti-affinity rules but this is just a nice quick way to get things moving.  The example below also shows the volume requests and mount in the use case of testing GPU Direct Storage over NFS.

~~~bash
$ cat <<EOF > nvidiatools-pod-nvd-srv-30.yaml
apiVersion: v1
kind: Pod
metadata:
  name: rdma-eth-30-workload
  namespace: default
  annotations:
    # JSON list is the canonical form; adjust if your NAD lives in another namespace
    k8s.v1.cni.cncf.io/networks: '[{ "name": "sriov-network" }]'
spec:
  serviceAccountName: nvidiatools
  nodeSelector:
    kubernetes.io/hostname: nvd-srv-30.nvidia.eng.rdu2.dc.redhat.com
  volumes:
    - name: rdma-pv-storage
      persistentVolumeClaim:
        claimName: pvc-netapp-phy-test
  containers:
    - name: rdma-30-workload
      image: quay.io/redhat_emp1/ecosys-nvidia/nvidia-tools:0.0.1
      imagePullPolicy: IfNotPresent
      securityContext:
        privileged: true
        capabilities:
          add: ["IPC_LOCK"]
      resources:
        limits:
          nvidia.com/gpu: 1
          openshift.io/sriovlegacy: 1
        requests:
          nvidia.com/gpu: 1
          openshift.io/sriovlegacy: 1
      volumeMounts:
        - name: rdma-pv-storage
          mountPath: /mnt
EOF
~~~

Once the custom resource file has been generated, create the resource on the cluster.

~~~bash
oc create -f mfttool-pod-nvd-srv-29.yaml
pod/mfttool-pod-nvd-srv-29 created
~~~

Validate that the pod is up and running.

~~~bash
$ oc get pods -n mfttool
NAME                     READY   STATUS    RESTARTS   AGE
mfttool-pod-nvd-srv-29   1/1     Running   0          28s
~~~

Next we can rsh into the pod.

~~~bash
$ oc rsh -n mfttool mfttool-pod-nvd-srv-29 
sh-5.1#
~~~

## What The Container Can Do

Once inside the pod we can run an `mst start` and then an `mst status` to see the devices.

~~~bash

sh-5.1# mst status
MST modules:
------------
    MST PCI module is not loaded
    MST PCI configuration module loaded

MST devices:
------------
/dev/mst/mt4129_pciconf0         - PCI configuration cycles access.
                                   domain:bus:dev.fn=0000:0d:00.0 addr.reg=88 data.reg=92 cr_bar.gw_offset=-1
                                   Chip revision is: 00
/dev/mst/mt4129_pciconf1         - PCI configuration cycles access.
                                   domain:bus:dev.fn=0000:37:00.0 addr.reg=88 data.reg=92 cr_bar.gw_offset=-1
                                   Chip revision is: 00

sh-5.1#
~~~

One of the things we can do with this container is query the devices and their settings with `mlxconfig`.  We can also change those settings like when we need to change a port from ethernet mode to infiniband mode.

~~~bash
mlxconfig -d /dev/mst/mt4129_pciconf0 query

Device #1:
----------

Device type:        ConnectX7           
Name:               MCX715105AS-WEAT_Ax 
Description:        NVIDIA ConnectX-7 HHHL Adapter Card; 400GbE (default mode) / NDR IB; Single-port QSFP112; Port Split Capable; PCIe 5.0 x16 with x16 PCIe extension option; Crypto Disabled; Secure Boot Enabled
Device:             /dev/mst/mt4129_pciconf0

Configurations:                                          Next Boot
        MODULE_SPLIT_M0                             Array[0..15]        
        MEMIC_BAR_SIZE                              0                   
        MEMIC_SIZE_LIMIT                            _256KB(1)           
       (...)
        ADVANCED_PCI_SETTINGS                       False(0)            
        SAFE_MODE_THRESHOLD                         10                  
        SAFE_MODE_ENABLE                            True(1)
~~~

Another tool in the container is `flint` which allows us to see the firmware, product version and PSID for the device.  This is useful for preparing for a firmware update.

~~~bash
flint -d /dev/mst/mt4129_pciconf0 query
Image type:            FS4
FW Version:            28.42.1000
FW Release Date:       8.8.2024
Product Version:       28.42.1000
Rom Info:              type=UEFI version=14.35.15 cpu=AMD64,AARCH64
                       type=PXE version=3.7.500 cpu=AMD64
Description:           UID                GuidsNumber
Base GUID:             e09d730300126474        16
Base MAC:              e09d73126474            16
Image VSD:             N/A
Device VSD:            N/A
PSID:                  MT_0000001244
Security Attributes:   secure-fw
~~~

Another tool in the container is `mlxup` which is an automated way to update the firmware.  When we run `mlxup` it queries all devices on the system and reports back the current firmware and what available firmware there is for the device.  We can then decide to update the cards or skip for now.  In the example below I have two single port CX-7 cards in the node my pod is running on and I will upgrade their firmware.

~~~bash
$ mlxup
Querying Mellanox devices firmware ...

Device #1:
----------

  Device Type:      ConnectX7
  Part Number:      MCX715105AS-WEAT_Ax
  Description:      NVIDIA ConnectX-7 HHHL Adapter Card; 400GbE (default mode) / NDR IB; Single-port QSFP112; Port Split Capable; PCIe 5.0 x16 with x16 PCIe extension option; Crypto Disabled; Secure Boot Enabled
  PSID:             MT_0000001244
  PCI Device Name:  /dev/mst/mt4129_pciconf1
  Base MAC:         e09d73125fc4
  Versions:         Current        Available     
     FW             28.42.1000     28.43.1014    
     PXE            3.7.0500       N/A           
     UEFI           14.35.0015     N/A           

  Status:           Update required

Device #2:
----------

  Device Type:      ConnectX7
  Part Number:      MCX715105AS-WEAT_Ax
  Description:      NVIDIA ConnectX-7 HHHL Adapter Card; 400GbE (default mode) / NDR IB; Single-port QSFP112; Port Split Capable; PCIe 5.0 x16 with x16 PCIe extension option; Crypto Disabled; Secure Boot Enabled
  PSID:             MT_0000001244
  PCI Device Name:  /dev/mst/mt4129_pciconf0
  Base MAC:         e09d73126474
  Versions:         Current        Available     
     FW             28.42.1000     28.43.1014    
     PXE            3.7.0500       N/A           
     UEFI           14.35.0015     N/A           

  Status:           Update required

---------
Found 2 device(s) requiring firmware update...

Perform FW update? [y/N]: y
Device #1: Updating FW ...     
FSMST_INITIALIZE -   OK          
Writing Boot image component -   OK          
Done
Device #2: Updating FW ...     
FSMST_INITIALIZE -   OK          
Writing Boot image component -   OK          
Done

Restart needed for updates to take effect.
Log File: /tmp/mlxup_workdir/mlxup-20250109_190606_17886.log
~~~

Notice the firmware upgrade completed but we need to restart the cards for the changes to take effect.  We can use the `mlxfwreset` command to do this and then validate with the `flint` command that the card is running the new firmware.

~~~bash
sh-5.1# mlxfwreset -d /dev/mst/mt4129_pciconf0 reset -y

The reset level for device, /dev/mst/mt4129_pciconf0 is:

3: Driver restart and PCI reset
Continue with reset?[y/N] y
-I- Sending Reset Command To Fw             -Done
-I- Stopping Driver                         -Done
-I- Resetting PCI                           -Done
-I- Starting Driver                         -Done
-I- Restarting MST                          -Done
-I- FW was loaded successfully.

sh-5.1# flint -d /dev/mst/mt4129_pciconf0 query
Image type:            FS4
FW Version:            28.43.1014
FW Release Date:       7.11.2024
Product Version:       28.43.1014
Rom Info:              type=UEFI version=14.36.16 cpu=AMD64,AARCH64
                       type=PXE version=3.7.500 cpu=AMD64
Description:           UID                GuidsNumber
Base GUID:             e09d730300126474        16
Base MAC:              e09d73126474            16
Image VSD:             N/A
Device VSD:            N/A
PSID:                  MT_0000001244
Security Attributes:   secure-fw
~~~

We can repeat the same steps on the second card in the system to complete the firmware update. 

~~~bash
sh-5.1# mlxfwreset -d /dev/mst/mt4129_pciconf1 reset -y

The reset level for device, /dev/mst/mt4129_pciconf1 is:

3: Driver restart and PCI reset
Continue with reset?[y/N] y
-I- Sending Reset Command To Fw             -Done
-I- Stopping Driver                         -Done
-I- Resetting PCI                           -Done
-I- Starting Driver                         -Done
-I- Restarting MST                          -Done
-I- FW was loaded successfully.

sh-5.1# flint -d /dev/mst/mt4129_pciconf1 query
Image type:            FS4
FW Version:            28.43.1014
FW Release Date:       7.11.2024
Product Version:       28.43.1014
Rom Info:              type=UEFI version=14.36.16 cpu=AMD64,AARCH64
                       type=PXE version=3.7.500 cpu=AMD64
Description:           UID                GuidsNumber
Base GUID:             e09d730300125fc4        16
Base MAC:              e09d73125fc4            16
Image VSD:             N/A
Device VSD:            N/A
PSID:                  MT_0000001244
Security Attributes:   secure-fw
~~~

Once the firmware update has been completed and validate we can remove the container.
