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
- [MLX Tool Examples](#mlx-tool-examples)
- [Perftest Tool Examples](#perftest-tool-examples)
- [GPU Direct Storage Examples](#gpu-direct-storage-examples)
- [NCCL Test Example](#nccl-test-example)

## Building The Container

The first step is to make a nvidia-tools directory.

~~~bash
$ mkdir -p ~/nvidia-tools
$ cd nvidia-tools
~~~

Next we need to create the following dockerfile we will use to build the container.

~~~bash
$ cat <<EOF > dockerfile.tools 
# Start from UBI9 image
FROM registry.access.redhat.com/ubi9/ubi:latest

# Set work directory
WORKDIR /root

# Copy in packages not available in UBI repo
COPY show_gids /usr/bin/show_gids
COPY ibdev2netdev /usr/sbin/ibdev2netdev

# DNF install packages either from repo or locally
RUN dnf install wget procps-ng pciutils yum jq iputils ethtool net-tools kmod systemd-udev rpm-build gcc make git autoconf automake libtool -y
RUN dnf install fio usbutils infiniband-diags libglvnd-opengl libibumad librdmacm libxcb libxcb-devel libxkbcommon libxkbcommon-x11 pciutils-devel rdma-core-devel xcb-util xcb-util-image xcb-util-keysyms xcb-util-renderutil xcb-util-wm -y
RUN dnf install openmpi openmpi-devel openssh-server openssh-clients -y
RUN dnf install iperf3 -y

# Cleanup 
RUN dnf clean all

# Create NFS Test Mountpoints
RUN mkdir /nfsslow
RUN mkdir /nfsfast

# Fix OpenMPI
RUN ln -s /usr/include/openmpi-x86_64 /usr/lib64/openmpi/include

# Run container entrypoint
COPY entrypoint.sh /root/entrypoint.sh
RUN chmod +x /root/entrypoint.sh
COPY bashrc /root/.bashrc
RUN ssh-keygen -A
RUN yes y | ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa > /dev/null 
RUN cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
RUN chmod 600 /root/.ssh/authorized_keys
COPY config /root/.ssh/config

ENTRYPOINT ["/root/entrypoint.sh"]
~~~

One of the scripts that will get copied into the container when the dockerfile is run is the `entrypoint.sh` script.

~~~bash
$ cat <<EOF > entrypoint.sh 
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
./install.sh --without-kernel

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
dnf -y install libnccl-static libnccl-devel libnccl

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

# Return to root
cd /root

# Git clone nccl-tests repository
git clone https://github.com/NVIDIA/nccl-tests.git

# Change into nccl-tests
cd /root/nccl-tests

# Build nccl-tests
make MPI=1 MPI_HOME=/usr/lib64/openmpi

# Enable RDMA Sharp Plugins
cd /root
git clone https://github.com/Mellanox/nccl-rdma-sharp-plugins.git
cd nccl-rdma-sharp-plugins/
./autogen.sh
./configure --with-cuda=/usr/local/cuda-12.8/
make
make install

# Enable SSHD deamon on port 20024
mkdir -p /var/run/sshd && /usr/sbin/sshd -p 20024

# Echo to logs container is ready - Sleep container indefinitly

echo "-------------------------------------------------------------------"
echo "All components for the container have been Installed!"
echo "Testing and tool usage is Ready!"
echo "-------------------------------------------------------------------"
sleep infinity & wait
~~~

Now that we have our dockerfile and entrypoint script we can build the image.

~~~bash
$ podman build . -f dockerfile.tools -t quay.io/redhat_emp1/ecosys-nvidia/nvidia-tools:0.1.3
STEP 1/21: FROM registry.access.redhat.com/ubi9/ubi:latest
STEP 2/21: WORKDIR /root
--> Using cache 05ab94448a150a327f9d8b573e4f84dea1b92343b04625732ff95d2245d883d3
--> 05ab94448a15
STEP 3/21: COPY show_gids /usr/bin/show_gids
--> Using cache c311a8020674b1b165b5695be0ce32ded986b4b741b5d52bbf575aab050ea04a
--> c311a8020674
STEP 4/21: COPY ibdev2netdev /usr/sbin/ibdev2netdev
--> Using cache df91b2f89cad5c498646cc609d3762a19069217026f370fa72f5d56e5d28142c
--> df91b2f89cad
STEP 5/21: RUN dnf install wget procps-ng pciutils yum jq iputils ethtool net-tools kmod systemd-udev rpm-build gcc make git autoconf automake libtool -y
--> Using cache c2e169180778bf7b17bf168e587f51a45206b6b16c921425a695c920953daea6
--> c2e169180778
STEP 6/21: RUN dnf install fio usbutils infiniband-diags libglvnd-opengl libibumad librdmacm libxcb libxcb-devel libxkbcommon libxkbcommon-x11 pciutils-devel rdma-core-devel xcb-util xcb-util-image xcb-util-keysyms xcb-util-renderutil xcb-util-wm -y
--> Using cache 42c1747917d6b0f1fcee46b787abd35b03c88c41d59c52c3d85207c138406db9
--> 42c1747917d6
STEP 7/21: RUN dnf install openmpi openmpi-devel openssh-server openssh-clients -y
--> Using cache 47fcd649787cbdf236b50f7d3e6e095a5f540b164eb5f4d134b5d0f55b419fdb
--> 47fcd649787c
STEP 8/21: RUN dnf install iperf3 -y
--> Using cache 1f272f69ed6b40cda19e5403ded7ce7b07f385e117d9d4b8b54d18120f4ab905
--> 1f272f69ed6b
STEP 9/21: RUN dnf clean all
--> Using cache fae83187f68fc3bf2cd5618fda4cb2637d4c9953eb4865fea82b6af8afeca82a
--> fae83187f68f
STEP 10/21: RUN mkdir /nfsslow
--> Using cache cb297e6dc2188630002e1b6fd1d21b31d42a6498b6382f00646bcebef18872fc
--> cb297e6dc218
STEP 11/21: RUN mkdir /nfsfast
--> Using cache 393276419af248f96501a8af20c7c314347c68957e84b44f479db61d88cb32b5
--> 393276419af2
STEP 12/21: RUN ln -s /usr/include/openmpi-x86_64 /usr/lib64/openmpi/include
--> Using cache c8eaf451f4ad05e3e1e87873d31eba52f0b91c4431d9ae589de49fea49ef2c10
--> c8eaf451f4ad
STEP 13/21: COPY entrypoint.sh /root/entrypoint.sh
--> Using cache 8c8bc04cac33ec1cfdeeefddc5d8c4e02951b6ed20bc910a1f84297444154483
--> 8c8bc04cac33
STEP 14/21: RUN chmod +x /root/entrypoint.sh
--> Using cache cad265709071ced431b7dfb3bde881ab370b1f13ba09407e648b5b7f16b98555
--> cad265709071
STEP 15/21: COPY bashrc /root/.bashrc
--> Using cache b54a24b856ec06b23a50bf67a08b172c063f00db53969c8a1d5336b52dfb8306
--> b54a24b856ec
STEP 16/21: RUN ssh-keygen -A
--> Using cache 38aa06b903828821bae317e6e0e2c83c3443294195ae951da65d8c44626e13e0
--> 38aa06b90382
STEP 17/21: RUN yes y | ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa > /dev/null 
--> Using cache f7378e514bb30fa3ba124807efafa26a793e8612bde64654579dce1adf78a700
--> f7378e514bb3
STEP 18/21: RUN cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
--> Using cache a4f9a643cfea24a0ec5d6880f222726cf3669bf924783265ef71fa9605449d27
--> a4f9a643cfea
STEP 19/21: RUN chmod 600 /root/.ssh/authorized_keys
--> Using cache 0f0d8f6a53fefb46ee54481cee70991d31e530da58c1b6d34a1a2b0dad961e80
--> 0f0d8f6a53fe
STEP 20/21: COPY config /root/.ssh/config
--> Using cache 911336ec4acffdf0aad880c28c94eaae97dfa0fd223c23ca727b39c4034b093f
--> 911336ec4acf
STEP 21/21: ENTRYPOINT ["/root/entrypoint.sh"]
--> Using cache fb5d914c21df3aa194b7eb73a8759fa63f8a4fe2ec13893b720e09cfcb5ad1f9
COMMIT quay.io/redhat_emp1/ecosys-nvidia/nvidia-tools:0.1.3
--> fb5d914c21df
Successfully tagged quay.io/redhat_emp1/ecosys-nvidia/nvidia-tools:0.1.3
fb5d914c21df3aa194b7eb73a8759fa63f8a4fe2ec13893b720e09cfcb5ad1f9
~~~

Once the image is built we can push it up to a registry that is reachable by our OpenShift cluster.

~~~bash
$ podman push quay.io/redhat_emp1/ecosys-nvidia/nvidia-tools:0.1.3
Getting image source signatures
Copying blob 60635972945b skipped: already exists  
Copying blob facf1e7dd3e0 skipped: already exists  
Copying blob ec465ce79861 skipped: already exists  
Copying blob 2572fa3e0870 skipped: already exists  
Copying blob 47dbbf6d4685 skipped: already exists  
Copying blob 8dd3689de7d8 skipped: already exists  
Copying blob c75cf1675c85 done   | 
Copying blob 306c4f8ba87a done   | 
Copying blob fa0bab35ea3c done   | 
Copying blob b93a768f0e42 done   | 
Copying blob a7fad58b73b8 done   | 
Copying blob 2e552e0ceffd skipped: already exists  
Copying blob 464a638daffd done   | 
Copying blob 5deaf50e6367 done   | 
Copying blob 8a1a7e823043 done   | 
Copying blob eb1d854a6feb done   | 
Copying blob 3aee82783724 done   | 
Copying blob cbb396f837e0 done   | 
Copying blob cb993e3c4b86 done   | 
Copying blob 9a0e11680ebb done   | 
Copying config fb5d914c21 done   | 
Writing manifest to image destination
~~~

If everything looks good we can proceed to the next section.

## Running The Container

The container will need to run priviledged so we can access the hardware devices.  To do this we will create a `ServiceAccount` for it to run.

~~~bash
$ cat <<EOF > nvidiatools-serviceaccount.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nvidiatools
  namespace: default
EOF
~~~

Once the resource file is generated create it on the cluster.

~~~bash
$ oc create -f nvidiatools-serviceaccount.yaml
serviceaccount/nvidiatools created
~~~

Now that the project has been created assign the appropriate privileges to the service account.

~~~bash
$ oc -n default adm policy add-scc-to-user privileged -z nvidiatools
clusterrole.rbac.authorization.k8s.io/system:openshift:scc:privileged added: "nvidiatools"
~~~

Depending on what we want to do with the NVIDIA tools we might create one or two pods, the latter for doing RDMA testing between nodes.  I normally put a nodeSelector into the pod yaml to make sure it will run on the node where I want it to run.  This could probably be done with anti-affinity rules but this is just a nice quick way to get things moving.  The example below also shows the volume requests and mount in the use case of testing GPU Direct Storage over NFS.

~~~bash
$ cat <<EOF > nvidiatools-pod-nvd-srv-30.yaml
apiVersion: v1
kind: Pod
metadata:
  name: nvidiatools-30-workload
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
    - name: nvidiatools-30-workload
      image: quay.io/redhat_emp1/ecosys-nvidia/nvidia-tools:0.0.3
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
$ oc create -f nvidiatools-pod-nvd-srv-30.yaml
pod/nvidiatools-30-workload created
~~~

Validate that the pod is up and running.

~~~bash
$ oc get pods
NAME                      READY   STATUS    RESTARTS   AGE
nvidiatools-30-workload   1/1     Running   0          55s
~~~

Next we can rsh into the pod.

~~~bash
$ oc rsh nvidiatools-30-workload
sh-5.1#
~~~

## MLX Tool Examples

Inside the container we can work with a variety of the MLX tooling that is available.   One thing we can see are the interfaces for the Mellanox/NVIDIA network devices by issuing a `mlx status -v`.  The net-net1 signifies that the interface is actually the one associated to this container.

~~~bash
sh-5.1# mst status -v
MST modules:
------------
    MST PCI module is not loaded
    MST PCI configuration module is not loaded
PCI devices:
------------
DEVICE_TYPE             MST      PCI       RDMA            NET                                     NUMA  
NA                      NA       37:00.4   mlx5_5                                                  0     

NA                      NA       37:00.2   mlx5_3          net-net1                                0     

ConnectX7(rev:0)        NA       37:00.0   mlx5_1                                                  0     

NA                      NA       37:00.7   mlx5_8                                                  0     

NA                      NA       37:00.5   mlx5_6                                                  0     

NA                      NA       37:00.3   mlx5_4                                                  0     

NA                      NA       37:00.1   mlx5_2                                                  0     

ConnectX7(rev:0)        NA       0d:00.0   mlx5_0                                                  0     

NA                      NA       37:00.6   mlx5_7                                                  0 
~~~

One of the things we can do with this container is query the devices and their settings with `mlxconfig`.  We can also change those settings like when we need to change a port from ethernet mode to infiniband mode.  The example below used `egrep` to basically filter only the items we really want to see which in this case were SRIOV related.

~~~bash
mlxconfig -d 37:00.0 query | egrep 'Device type:|Name:|Description:|Configurations:|SRIOV_EN|LINK_TYPE|NUM_OF_VFS'
Device type:        ConnectX7           
Name:               MCX715105AS-WEAT_Ax 
Description:        NVIDIA ConnectX-7 HHHL Adapter Card; 400GbE (default mode) / NDR IB; Single-port QSFP112; Port Split Capable; PCIe 5.0 x16 with x16 PCIe extension option; Crypto Disabled; Secure Boot Enabled
Configurations:                                          Next Boot
        NUM_OF_VFS                                  8                   
        SRIOV_EN                                    True(1)             
        LINK_TYPE_P1                                ETH(2) 
~~~

Another tool in the container is `flint` which allows us to see the firmware, product version and PSID for the device.  This is useful for preparing for a firmware update.

~~~bash
flint -d 37:00.0 query
Image type:            FS4
FW Version:            28.43.1014
FW Release Date:       7.11.2024
Product Version:       28.43.1014
Rom Info:              type=UEFI version=14.36.16 cpu=AMD64,AARCH64
                       type=PXE version=3.7.500 cpu=AMD64
Description:           UID                GuidsNumber
Base GUID:             e09d730300126744        16
Base MAC:              e09d73126744            16
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

There are a bunch of other MLX tools built into the image so explore away.   However when ready we can proceed to looking at the Perftest tooling in the next section.

## Perftest Tool Examples

For the use of perftools we really need to deploy two pods that are on different worker nodes.   We can use the same pod yaml above but just set the nodeSelector appropriately and create the pods.

~~~bash
$ oc create -f nvidiatools-30-workload.yaml 
pod/nvidiatools-30-workload created

$ oc create -f nvidiatools-29-workload.yaml 
pod/nvidiatools-29-workload created
~~~

Validate the pods are up and running.

~~~bash
$ oc get pods
NAME                     READY   STATUS    RESTARTS   AGE
nvidiatools-29-workload   1/1     Running   0          51s
nvidiatools-30-workload   1/1     Running   0          47s
~~~

Now open two terminals and `rsh` into each pod in one of the terminals and validate that the perftest commands are present.  We can also get the ipaddress of our pod inside the containers.

~~~bash
$ oc rsh nvidiatools-30-workload
sh-5.1# ib
ib_atomic_bw         ib_read_lat          ib_write_bw          ibcacheedit          ibfindnodesusing.pl  iblinkinfo           ibping               ibroute              ibstatus             ibtracert            
ib_atomic_lat        ib_send_bw           ib_write_lat         ibccconfig           ibhosts              ibnetdiscover        ibportstate          ibrouters            ibswitches           
ib_read_bw           ib_send_lat          ibaddr               ibccquery            ibidsverify.pl       ibnodes              ibqueryerrors        ibstat               ibsysstat            
sh-5.1# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
2: eth0@if96: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1400 qdisc noqueue state UP group default 
    link/ether 0a:58:0a:83:00:34 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 10.131.0.52/23 brd 10.131.1.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 fe80::858:aff:fe83:34/64 scope link 
       valid_lft forever preferred_lft forever
3: net1@if78: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default 
    link/ether 32:1a:83:4a:e2:39 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 192.168.2.1/24 brd 192.168.2.255 scope global net1
       valid_lft forever preferred_lft forever
    inet6 fe80::301a:83ff:fe4a:e239/64 scope link 
       valid_lft forever preferred_lft forever

$ oc rsh nvidiatools-29-workload
sh-5.1# ib
ib_atomic_bw         ib_read_lat          ib_write_bw          ibcacheedit          ibfindnodesusing.pl  iblinkinfo           ibping               ibroute              ibstatus             ibtracert            
ib_atomic_lat        ib_send_bw           ib_write_lat         ibccconfig           ibhosts              ibnetdiscover        ibportstate          ibrouters            ibswitches           
ib_read_bw           ib_send_lat          ibaddr               ibccquery            ibidsverify.pl       ibnodes              ibqueryerrors        ibstat               ibsysstat            
sh-5.1# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
2: eth0@if105: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1400 qdisc noqueue state UP group default 
    link/ether 0a:58:0a:80:02:3d brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 10.128.2.61/23 brd 10.128.3.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 fe80::858:aff:fe80:23d/64 scope link 
       valid_lft forever preferred_lft forever
3: net1@if82: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default 
    link/ether 22:3e:02:c9:d0:87 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 192.168.2.2/24 brd 192.168.2.255 scope global net1
       valid_lft forever preferred_lft forever
    inet6 fe80::203e:2ff:fec9:d087/64 scope link 
       valid_lft forever preferred_lft forever
~~~

Now let's run the RDMA perftest with the `--use_cuda` switch.  Again we will need to have two `rsh` sessions one on each pod.  In the first terminal we can run the following.

~~~bash
sh-5.1# ib_write_bw -R -T 41 -s 65536 -F -x 3 -m 4096 --report_gbits -q 16 -D 60  -d mlx5_1 -p 10000 --source_ip 192.168.2.1 --use_cuda=0 --use_cuda_dmabuf
 WARNING: BW peak won't be measured in this run.
Perftest doesn't supports CUDA tests with inline messages: inline size set to 0

************************************
* Waiting for client to connect... *
************************************
~~~~

In the second terminal we will run the following command which will dump the output.

~~~bash
sh-5.1# ib_write_bw -R -T 41 -s 65536 -F -x 3 -m 4096 --report_gbits -q 16 -D 60  -d mlx5_1 -p 10000 --source_ip 192.168.2.2 --use_cuda=0 192.168.2.1 --use_cuda_dmabuf
 WARNING: BW peak won't be measured in this run.
Perftest doesn't supports CUDA tests with inline messages: inline size set to 0
Requested mtu is higher than active mtu 
Changing to active mtu - 3
initializing CUDA
Listing all CUDA devices in system:
CUDA device 0: PCIe address is E1:00

Picking device No. 0
[pid = 4101, dev = 0] device name = [NVIDIA A40]
creating CUDA Ctx
making it the current CUDA Ctx
CUDA device integrated: 0
cuMemAlloc() of a 2097152 bytes GPU buffer
allocated GPU buffer address at 00007f3dfa600000 pointer=0x7f3dfa600000
---------------------------------------------------------------------------------------
                    RDMA_Write BW Test
 Dual-port       : OFF		Device         : mlx5_1
 Number of qps   : 16		Transport type : IB
 Connection type : RC		Using SRQ      : OFF
 PCIe relax order: ON		Lock-free      : OFF
 ibv_wr* API     : ON		Using DDP      : OFF
 TX depth        : 128
 CQ Moderation   : 1
 Mtu             : 1024[B]
 Link type       : Ethernet
 GID index       : 3
 Max inline data : 0[B]
 rdma_cm QPs	 : ON
 Data ex. method : rdma_cm 	TOS    : 41
---------------------------------------------------------------------------------------
 local address: LID 0000 QPN 0x00c6 PSN 0x2986aa
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 local address: LID 0000 QPN 0x00c7 PSN 0xa0ef83
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 local address: LID 0000 QPN 0x00c8 PSN 0x74badb
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 local address: LID 0000 QPN 0x00c9 PSN 0x287d57
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 local address: LID 0000 QPN 0x00ca PSN 0xf5b155
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 local address: LID 0000 QPN 0x00cb PSN 0x6cc15d
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 local address: LID 0000 QPN 0x00cc PSN 0x3730c2
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 local address: LID 0000 QPN 0x00cd PSN 0x74d75d
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 local address: LID 0000 QPN 0x00ce PSN 0x51a707
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 local address: LID 0000 QPN 0x00cf PSN 0x987246
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 local address: LID 0000 QPN 0x00d0 PSN 0xa334a8
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 local address: LID 0000 QPN 0x00d1 PSN 0x5d8f52
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 local address: LID 0000 QPN 0x00d2 PSN 0xc42ca0
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 local address: LID 0000 QPN 0x00d3 PSN 0xf43696
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 local address: LID 0000 QPN 0x00d4 PSN 0x43f9d2
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 local address: LID 0000 QPN 0x00d5 PSN 0xbc4d64
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 remote address: LID 0000 QPN 0x00c6 PSN 0xb1023e
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 remote address: LID 0000 QPN 0x00c7 PSN 0xc78587
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 remote address: LID 0000 QPN 0x00c8 PSN 0x5a328f
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 remote address: LID 0000 QPN 0x00c9 PSN 0x582cfb
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 remote address: LID 0000 QPN 0x00cb PSN 0x40d229
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 remote address: LID 0000 QPN 0x00cc PSN 0x5833a1
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 remote address: LID 0000 QPN 0x00cd PSN 0xcfefb6
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 remote address: LID 0000 QPN 0x00ce PSN 0xfd5d41
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 remote address: LID 0000 QPN 0x00cf PSN 0xed811b
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 remote address: LID 0000 QPN 0x00d0 PSN 0x5244ca
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 remote address: LID 0000 QPN 0x00d1 PSN 0x946edc
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 remote address: LID 0000 QPN 0x00d2 PSN 0x4e0f76
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 remote address: LID 0000 QPN 0x00d3 PSN 0x7b13f4
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 remote address: LID 0000 QPN 0x00d4 PSN 0x1a2d5a
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 remote address: LID 0000 QPN 0x00d5 PSN 0xd22346
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 remote address: LID 0000 QPN 0x00d6 PSN 0x722bc8
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
---------------------------------------------------------------------------------------
 #bytes     #iterations    BW peak[Gb/sec]    BW average[Gb/sec]   MsgRate[Mpps]
 65536      10384867         0.00               181.46 		     0.346100
---------------------------------------------------------------------------------------
deallocating GPU buffer 00007f3dfa600000
destroying current CUDA Ctx
~~~

And if we return to the first terminal we should see it updated with the same output.

~~~bash
sh-5.1# ib_write_bw -R -T 41 -s 65536 -F -x 3 -m 4096 --report_gbits -q 16 -D 60  -d mlx5_1 -p 10000 --source_ip 192.168.2.1 --use_cuda=0 --use_cuda_dmabuf
 WARNING: BW peak won't be measured in this run.
Perftest doesn't supports CUDA tests with inline messages: inline size set to 0

************************************
* Waiting for client to connect... *
************************************
Requested mtu is higher than active mtu 
Changing to active mtu - 3
initializing CUDA
Listing all CUDA devices in system:
CUDA device 0: PCIe address is 61:00

Picking device No. 0
[pid = 4109, dev = 0] device name = [NVIDIA A40]
creating CUDA Ctx
making it the current CUDA Ctx
CUDA device integrated: 0
cuMemAlloc() of a 2097152 bytes GPU buffer
allocated GPU buffer address at 00007f8bca600000 pointer=0x7f8bca600000
---------------------------------------------------------------------------------------
                    RDMA_Write BW Test
 Dual-port       : OFF		Device         : mlx5_1
 Number of qps   : 16		Transport type : IB
 Connection type : RC		Using SRQ      : OFF
 PCIe relax order: ON		Lock-free      : OFF
 ibv_wr* API     : ON		Using DDP      : OFF
 CQ Moderation   : 1
 Mtu             : 1024[B]
 Link type       : Ethernet
 GID index       : 3
 Max inline data : 0[B]
 rdma_cm QPs	 : ON
 Data ex. method : rdma_cm 	TOS    : 41
---------------------------------------------------------------------------------------
 Waiting for client rdma_cm QP to connect
 Please run the same command with the IB/RoCE interface IP
---------------------------------------------------------------------------------------
 local address: LID 0000 QPN 0x00c6 PSN 0xb1023e
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 local address: LID 0000 QPN 0x00c7 PSN 0xc78587
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 local address: LID 0000 QPN 0x00c8 PSN 0x5a328f
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 local address: LID 0000 QPN 0x00c9 PSN 0x582cfb
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 local address: LID 0000 QPN 0x00cb PSN 0x40d229
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 local address: LID 0000 QPN 0x00cc PSN 0x5833a1
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 local address: LID 0000 QPN 0x00cd PSN 0xcfefb6
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 local address: LID 0000 QPN 0x00ce PSN 0xfd5d41
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 local address: LID 0000 QPN 0x00cf PSN 0xed811b
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 local address: LID 0000 QPN 0x00d0 PSN 0x5244ca
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 local address: LID 0000 QPN 0x00d1 PSN 0x946edc
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 local address: LID 0000 QPN 0x00d2 PSN 0x4e0f76
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 local address: LID 0000 QPN 0x00d3 PSN 0x7b13f4
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 local address: LID 0000 QPN 0x00d4 PSN 0x1a2d5a
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 local address: LID 0000 QPN 0x00d5 PSN 0xd22346
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 local address: LID 0000 QPN 0x00d6 PSN 0x722bc8
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:32
 remote address: LID 0000 QPN 0x00c6 PSN 0x2986aa
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 remote address: LID 0000 QPN 0x00c7 PSN 0xa0ef83
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 remote address: LID 0000 QPN 0x00c8 PSN 0x74badb
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 remote address: LID 0000 QPN 0x00c9 PSN 0x287d57
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 remote address: LID 0000 QPN 0x00ca PSN 0xf5b155
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 remote address: LID 0000 QPN 0x00cb PSN 0x6cc15d
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 remote address: LID 0000 QPN 0x00cc PSN 0x3730c2
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 remote address: LID 0000 QPN 0x00cd PSN 0x74d75d
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 remote address: LID 0000 QPN 0x00ce PSN 0x51a707
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 remote address: LID 0000 QPN 0x00cf PSN 0x987246
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 remote address: LID 0000 QPN 0x00d0 PSN 0xa334a8
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 remote address: LID 0000 QPN 0x00d1 PSN 0x5d8f52
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 remote address: LID 0000 QPN 0x00d2 PSN 0xc42ca0
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 remote address: LID 0000 QPN 0x00d3 PSN 0xf43696
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 remote address: LID 0000 QPN 0x00d4 PSN 0x43f9d2
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
 remote address: LID 0000 QPN 0x00d5 PSN 0xbc4d64
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:06:145:33
---------------------------------------------------------------------------------------
 #bytes     #iterations    BW peak[Gb/sec]    BW average[Gb/sec]   MsgRate[Mpps]
 65536      10384867         0.00               181.46 		     0.346100
---------------------------------------------------------------------------------------
deallocating GPU buffer 00007f8bca600000
destroying current CUDA Ctx
~~~

## GPU Direct Storage Examples

Finally there are the GPU Direct Storage tools that come with the container as well.  The following pod yaml defines this configuration.  This assumes the OpenShift cluster has been configured appropriately for the use of GPU Direct Storage for Netapp which is documented [here](https://github.com/schmaustech/ocp-gds-netapp)

~~~bash
$ cat <<EOF > nvidiatools-30-workload.yaml 
apiVersion: v1
kind: Pod
metadata:
  name: nvidiatools-30-workload
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
    - name: nordma-pv-storage
      persistentVolumeClaim:
        claimName: pvc-netapp-phy-nordma-test
  containers:
    - name: nvidiatools-30-workload
      image: quay.io/redhat_emp1/ecosys-nvidia/nvidia-tools:0.0.3
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
          mountPath: /nfsfast
        - name: nordma-pv-storage
          mountPath: /nfsslow
EOF
~~~

~~~bash
$ oc create -f nvidiatools-30-workload.yaml 
nvidiatools-30-workload created

$ oc get pods
NAME                 READY   STATUS    RESTARTS   AGE
nvidiatools-30-workload   1/1     Running   0          3s
~~~

Once the pod is up and running we can `rsh` into the pod and run the `gdscheck` tool to confirm capabilities and configuration of GPU Direct Storage.

~~~bash
$ oc rsh nvidiatools-30-workload
        
sh-5.1# /usr/local/cuda/gds/tools/gdscheck -p
 GDS release version: 1.13.1.3
 nvidia_fs version:  2.20 libcufile version: 2.12
 Platform: x86_64
 ============
 ENVIRONMENT:
 ============
 =====================
 DRIVER CONFIGURATION:
 =====================
 NVMe P2PDMA        : Unsupported
 NVMe               : Supported
 NVMeOF             : Supported
 SCSI               : Unsupported
 ScaleFlux CSD      : Unsupported
 NVMesh             : Unsupported
 DDN EXAScaler      : Unsupported
 IBM Spectrum Scale : Unsupported
 NFS                : Supported
 BeeGFS             : Unsupported
 WekaFS             : Unsupported
 Userspace RDMA     : Unsupported
 --Mellanox PeerDirect : Disabled
 --rdma library        : Not Loaded (libcufile_rdma.so)
 --rdma devices        : Not configured
 --rdma_device_status  : Up: 0 Down: 0
 =====================
 CUFILE CONFIGURATION:
 =====================
 properties.use_pci_p2pdma : false
 properties.use_compat_mode : true
 properties.force_compat_mode : false
 properties.gds_rdma_write_support : true
 properties.use_poll_mode : false
 properties.poll_mode_max_size_kb : 4
 properties.max_batch_io_size : 128
 properties.max_batch_io_timeout_msecs : 5
 properties.max_direct_io_size_kb : 16384
 properties.max_device_cache_size_kb : 131072
 properties.max_device_pinned_mem_size_kb : 33554432
 properties.posix_pool_slab_size_kb : 4 1024 16384 
 properties.posix_pool_slab_count : 128 64 64 
 properties.rdma_peer_affinity_policy : RoundRobin
 properties.rdma_dynamic_routing : 0
 fs.generic.posix_unaligned_writes : false
 fs.lustre.posix_gds_min_kb: 0
 fs.beegfs.posix_gds_min_kb: 0
 fs.weka.rdma_write_support: false
 fs.gpfs.gds_write_support: false
 fs.gpfs.gds_async_support: true
 profile.nvtx : false
 profile.cufile_stats : 0
 miscellaneous.api_check_aggressive : false
 execution.max_io_threads : 4
 execution.max_io_queue_depth : 128
 execution.parallel_io : true
 execution.min_io_threshold_size_kb : 8192
 execution.max_request_parallelism : 4
 properties.force_odirect_mode : false
 properties.prefer_iouring : false
 =========
 GPU INFO:
 =========
 GPU index 0 NVIDIA L40S bar:1 bar size (MiB):65536 supports GDS, IOMMU State: Disabled
 ==============
 PLATFORM INFO:
 ==============
 IOMMU: disabled
 Nvidia Driver Info Status: Supported(Nvidia Open Driver Installed)
 Cuda Driver Version Installed:  12080
 Platform: PowerEdge R760xa, Arch: x86_64(Linux 5.14.0-427.65.1.el9_4.x86_64)
 Platform verification succeeded
~~~

Now let's confirm our GPU Direct NFS mount is mounted.  Notice in the output the proto is rdma.

~~~bash
sh-5.1# mount|grep nfs
192.168.10.101:/trident_pvc_ae477c5c_cf10_4bc0_bb71_39d214a237f0 on /mnt type nfs4 (rw,relatime,vers=4.1,rsize=262144,wsize=262144,namlen=255,hard,proto=rdma,max_connect=16,port=20049,timeo=600,retrans=2,sec=sys,clientaddr=192.168.10.30,local_lock=none,write=eager,addr=192.168.10.101)
~~~

Next we can use `gdsio` to run some benchmarks across the GPU Direct NFS mount.  Before we run the benchmarks let's familiarize ourselves with the all the `gdsio` switches and what they mean.

~~~bash
sh-5.1# /usr/local/cuda-12.8/gds/tools/gdsio -h
gdsio version :1.12
Usage [using config file]: gdsio rw-sample.gdsio
Usage [using cmd line options]:/usr/local/cuda-12.8/gds/tools/gdsio 
         -f <file name>
         -D <directory name>
         -d <gpu_index (refer nvidia-smi)>
         -n <numa node>
         -m <memory type(0 - (cudaMalloc), 1 - (cuMem), 2 - (cudaMallocHost), 3 - (malloc) 4 - (mmap))>
         -w <number of threads for a job>
         -s <file size(K|M|G)>
         -o <start offset(K|M|G)>
         -i <io_size(K|M|G)> <min_size:max_size:step_size>
         -p <enable nvlinks> 
         -b <skip bufregister> 
         -V <verify IO>
         -x <xfer_type> [0(GPU_DIRECT), 1(CPU_ONLY), 2(CPU_GPU), 3(CPU_ASYNC_GPU), 4(CPU_CACHED_GPU), 5(GPU_DIRECT_ASYNC), 6(GPU_BATCH), 7(GPU_BATCH_STREAM)]
         -B <batch size>
         -I <(read) 0|(write)1| (randread) 2| (randwrite) 3>
         -T <duration in seconds>
         -k <random_seed> (number e.g. 3456) to be used with random read/write> 
         -U <use unaligned(4K) random offsets>
         -R <fill io buffer with random data>
         -F <refill io buffer with random data during each write>
         -a <alignment size in case of random IO>
         -M <mixed_rd_wr_percentage in case of regular batch mode>
         -P <rdma url>
         -J <per job statistics>

xfer_type:
0 - Storage->GPU (GDS)
1 - Storage->CPU
2 - Storage->CPU->GPU
3 - Storage->CPU->GPU_ASYNC
4 - Storage->PAGE_CACHE->CPU->GPU
5 - Storage->GPU_ASYNC
6 - Storage->GPU_BATCH
7 - Storage->GPU_BATCH_STREAM

Note:
read test (-I 0) with verify option (-V) should be used with files written (-I 1) with -V option
read test (-I 2) with verify option (-V) should be used with files written (-I 3) with -V option, using same random seed (-k),
same number of threads(-w), offset(-o), and data size(-s)
write test (-I 1/3) with verify option (-V) will perform writes followed by read
~~~

Before we begin running some tests I want to note that the tests are being run from a standard Dell R760xa and from the `nvidia-smi` topo output we can see we are dealing with a non optimal setup of NODE where the connection traversing PCIe as well as the interconnect between PCIe Host Bridges within a NUMA node.  Ideally for peformant numbers we would want to run this on a H100 or B200 where the GPU and NIC are connected to the same PCIe switch and yield a PHB,PXB or PIX connection.

~~~bash
sh-5.1# nvidia-smi topo -mp
	    GPU0	NIC0	NIC1	NIC2	NIC3	NIC4	NIC5	NIC6	NIC7	NIC8	NIC9	CPU Affinity	NUMA Affinity	GPU NUMA ID
GPU0	 X 	NODE	NODE	NODE	NODE	NODE	NODE	NODE	NODE	NODE	NODE	0,2,4,6,8,10	0		N/A
NIC0	NODE	 X 	NODE	NODE	NODE	NODE	NODE	NODE	NODE	NODE	NODE				
NIC1	NODE	NODE	 X 	PIX	PIX	PIX	PIX	PIX	PIX	PIX	PIX				
NIC2	NODE	NODE	PIX	 X 	PIX	PIX	PIX	PIX	PIX	PIX	PIX				
NIC3	NODE	NODE	PIX	PIX	 X 	PIX	PIX	PIX	PIX	PIX	PIX				
NIC4	NODE	NODE	PIX	PIX	PIX	 X 	PIX	PIX	PIX	PIX	PIX				
NIC5	NODE	NODE	PIX	PIX	PIX	PIX	 X 	PIX	PIX	PIX	PIX				
NIC6	NODE	NODE	PIX	PIX	PIX	PIX	PIX	 X 	PIX	PIX	PIX				
NIC7	NODE	NODE	PIX	PIX	PIX	PIX	PIX	PIX	 X 	PIX	PIX				
NIC8	NODE	NODE	PIX	PIX	PIX	PIX	PIX	PIX	PIX	 X 	PIX				
NIC9	NODE	NODE	PIX	PIX	PIX	PIX	PIX	PIX	PIX	PIX	 X 				

Legend:

  X    = Self
  SYS  = Connection traversing PCIe as well as the SMP interconnect between NUMA nodes (e.g., QPI/UPI)
  NODE = Connection traversing PCIe as well as the interconnect between PCIe Host Bridges within a NUMA node
  PHB  = Connection traversing PCIe as well as a PCIe Host Bridge (typically the CPU)
  PXB  = Connection traversing multiple PCIe bridges (without traversing the PCIe Host Bridge)
  PIX  = Connection traversing at most a single PCIe bridge

NIC Legend:

  NIC0: mlx5_0
  NIC1: mlx5_1
  NIC2: mlx5_2
  NIC3: mlx5_3
  NIC4: mlx5_4
  NIC5: mlx5_5
  NIC6: mlx5_6
  NIC7: mlx5_7
  NIC8: mlx5_8
  NIC9: mlx5_9
~~~

Now let's run a few `gdsio` tests across our RDMA nfs mount.  In this first example, gdsio is used to generate a random write load of small IOs (4k) to one of the NFS mount point

~~~bash
sh-5.1# /usr/local/cuda-12.8/gds/tools/gdsio -D /nfsfast -d 0 -w 32 -s 500M -i 4K -x 0 -I 3 -T 120
IoType: RANDWRITE XferType: GPUD Threads: 32 DataSetSize: 43222136/16384000(KiB) IOSize: 4(KiB) Throughput: 0.344940 GiB/sec, Avg_Latency: 352.314946 usecs ops: 10805534 total_time 119.498576 secs
~~~

Next we will repeat the same test but for random reads.

~~~bash
sh-5.1# /usr/local/cuda-12.8/gds/tools/gdsio -D /nfsfast -d 0 -w 32 -s 500M -i 4K -x 0 -I 2 -T 120
IoType: RANDREAD XferType: GPUD Threads: 32 DataSetSize: 71313540/16384000(KiB) IOSize: 4(KiB) Throughput: 0.569229 GiB/sec, Avg_Latency: 214.448246 usecs ops: 17828385 total_time 119.477201 secs
~~~

Small and random IOs are all about IOPS and latency. For our next test we will determine throughput.  We will use larger files sizes and much larger IO sizes.

~~~bash
sh-5.1# /usr/local/cuda-12.8/gds/tools/gdsio -D /nfsfast -d 0 -w 32 -s 1G -i 1M -x 0 -I 1 -T 120
IoType: WRITE XferType: GPUD Threads: 32 DataSetSize: 320301056/33554432(KiB) IOSize: 1024(KiB) Throughput: 2.547637 GiB/sec, Avg_Latency: 12487.658159 usecs ops: 312794 total_time 119.900455 secs
~~~

This concludes the workflow of configuring and testing GPU Direct Storage on OpenShift over an RDMA NFS mount.

## NCCL Test Example

The following is an example using the NCCL tests that are part of the container image.   It assumes one of the pod yamls above have been deployed on two different worker nodes in the cluster that have a secondary RDMA interface and also a GPU allocated to them.

Here is an example of the pod yaml that I used for both pods only changing the hostname.

~~~bash
apiVersion: v1
kind: Pod
metadata:
  name: nvidiatools-30-workload
  namespace: default
  annotations:
    # JSON list is the canonical form; adjust if your NAD lives in another namespace
    k8s.v1.cni.cncf.io/networks: '[{ "name": "sriov-network" }]'
spec:
  serviceAccountName: nvidiatools
  nodeSelector:
    kubernetes.io/hostname: nvd-srv-30.nvidia.eng.rdu2.dc.redhat.com
  volumes:
    - name: shmem
      emptyDir: {
          medium: 'Memory',
          sizeLimit: '16Gi'
      }
  containers:
    - name: nvidiatools-30-workload
      image: quay.io/redhat_emp1/ecosys-nvidia/nvidia-tools:0.1.1
      imagePullPolicy: IfNotPresent
      securityContext:
        privileged: true
        capabilities:
          add: ["IPC_LOCK"]
      resources:
        limits:
          nvidia.com/gpu: 2
          openshift.io/sriovlegacy: 1
        requests:
          nvidia.com/gpu: 2
          openshift.io/sriovlegacy: 1
      volumeMounts:
      volumeMounts:
        - mountPath: /dev/shm
          name: shmem
~~~

Let's confirm we have our pods running.  In the case below they are in the default namespace.

~~~bash
$ oc get pods
NAME                      READY   STATUS    RESTARTS   AGE
nvidiatools-29-workload   1/1     Running   0          4h58m
nvidiatools-30-workload   1/1     Running   0          4h58m
~~~

We will need to open two terminal sessions, one into each pod.   Inside we can then source the `.bashrc` which will set our pathing appropriately.

~~~bash
sh-5.1# source ./.bashrc
~~~

We also need to run the `show_gids` command determine which Mellanox devices are present.  We will use this information for the next step.

~~~bash
[root@nvidiatools-30-workload ~]# show_gids
DEV	PORT	INDEX	GID					IPv4  		VER	DEV
---	----	-----	---					------------  	---	---
mlx5_3	1	0	fe80:0000:0000:0000:0cb0:10ff:fe34:0aad			v1	net1
mlx5_3	1	1	fe80:0000:0000:0000:0cb0:10ff:fe34:0aad			v2	net1
mlx5_3	1	2	0000:0000:0000:0000:0000:ffff:c0a8:0a02	192.168.10.2  	v1	net1
mlx5_3	1	3	0000:0000:0000:0000:0000:ffff:c0a8:0a02	192.168.10.2  	v2	net1
n_gids_found=4
~~~

Now we can actually do our mpirun across the two worker nodes.  

~~~bash
[root@nvidiatools-29-workload nccl-tests]# mpirun --allow-run-as-root -H 192.168.10.1:1,192.168.10.2:1 -np 2 -bind-to none -map-by slot -mca pml ob1 -mca btl ^openib -mca btl_tcp_if_include 192.168.10.0/24 -mca plm_rsh_args "-p 20024" -x NCCL_IB_DISABLE=1 -x NCCL_DEBUG=VERSION -x NCCL_SOCKET_IFNAME=net1 -x NCCL_IB_HCA=mlx5_1,mlx5_3 -x UCX_NET_DEVICES=net1 -x NCCL_NET_GDR_READ=1 ./build/all_reduce_perf -b 8 -e 16G -f2 -g 1
# nThread 1 nGpus 1 minBytes 8 maxBytes 17179869184 step: 2(factor) warmup iters: 5 iters: 20 agg iters: 1 validation: 1 graph: 0
#
# Using devices
#  Rank  0 Group  0 Pid  14744 on nvidiatools-29-workload device  0 [0000:61:00] NVIDIA L40S
#  Rank  1 Group  0 Pid  13965 on nvidiatools-30-workload device  0 [0000:61:00] NVIDIA L40S
#
# Reducing maxBytes to 15534478677 due to memory limitation
NCCL version 2.27.3+cuda12.9
#
#                                                              out-of-place                       in-place          
#       size         count      type   redop    root     time   algbw   busbw #wrong     time   algbw   busbw #wrong
#        (B)    (elements)                               (us)  (GB/s)  (GB/s)            (us)  (GB/s)  (GB/s)       
           8             2     float     sum      -1    13.24    0.00    0.00      0    12.25    0.00    0.00      0
          16             4     float     sum      -1    12.05    0.00    0.00      0    12.23    0.00    0.00      0
          32             8     float     sum      -1    12.31    0.00    0.00      0    12.27    0.00    0.00      0
          64            16     float     sum      -1    12.32    0.01    0.01      0    12.30    0.01    0.01      0
         128            32     float     sum      -1    12.61    0.01    0.01      0    12.81    0.01    0.01      0
         256            64     float     sum      -1    12.60    0.02    0.02      0    12.46    0.02    0.02      0
         512           128     float     sum      -1    12.83    0.04    0.04      0    12.62    0.04    0.04      0
        1024           256     float     sum      -1    12.88    0.08    0.08      0    12.89    0.08    0.08      0
        2048           512     float     sum      -1    13.47    0.15    0.15      0    13.27    0.15    0.15      0
        4096          1024     float     sum      -1    14.41    0.28    0.28      0    14.12    0.29    0.29      0
        8192          2048     float     sum      -1    15.39    0.53    0.53      0    15.38    0.53    0.53      0
       16384          4096     float     sum      -1    17.93    0.91    0.91      0    17.94    0.91    0.91      0
       32768          8192     float     sum      -1    21.73    1.51    1.51      0    21.31    1.54    1.54      0
       65536         16384     float     sum      -1    29.88    2.19    2.19      0    29.54    2.22    2.22      0
      131072         32768     float     sum      -1    46.95    2.79    2.79      0    46.43    2.82    2.82      0
      262144         65536     float     sum      -1    84.37    3.11    3.11      0    83.04    3.16    3.16      0
      524288        131072     float     sum      -1    159.9    3.28    3.28      0    157.2    3.34    3.34      0
     1048576        262144     float     sum      -1    166.4    6.30    6.30      0    167.9    6.24    6.24      0
     2097152        524288     float     sum      -1    297.6    7.05    7.05      0    296.2    7.08    7.08      0
     4194304       1048576     float     sum      -1    556.3    7.54    7.54      0    554.9    7.56    7.56      0
     8388608       2097152     float     sum      -1   1070.0    7.84    7.84      0   1071.4    7.83    7.83      0
    16777216       4194304     float     sum      -1   2128.7    7.88    7.88      0   2123.3    7.90    7.90      0
    33554432       8388608     float     sum      -1   4243.4    7.91    7.91      0   4241.1    7.91    7.91      0
    67108864      16777216     float     sum      -1   8459.9    7.93    7.93      0   8468.1    7.92    7.92      0
   134217728      33554432     float     sum      -1    16969    7.91    7.91      0    16919    7.93    7.93      0
   268435456      67108864     float     sum      -1    33816    7.94    7.94      0    33794    7.94    7.94      0
   536870912     134217728     float     sum      -1    66984    8.01    8.01      0    67062    8.01    8.01      0
  1073741824     268435456     float     sum      -1   134471    7.98    7.98      0   134020    8.01    8.01      0
  2147483648     536870912     float     sum      -1   266806    8.05    8.05      0   267080    8.04    8.04      0
  4294967296    1073741824     float     sum      -1   530413    8.10    8.10      0   527640    8.14    8.14      0
  8589934592    2147483648     float     sum      -1  1059765    8.11    8.11      0  1058307    8.12    8.12      0
# Out of bounds values : 0 OK
# Avg bus bandwidth    : 3.98762 
#
~~~

This second run is just like the first except we have allocated 2 GPUs per pods instead of just 1 as in the first test run.

~~~bash
[root@nvidiatools-29-workload ~]# mpirun --allow-run-as-root -H 192.168.10.1:1,192.168.10.2:1 -np 2 -bind-to none -map-by slot -mca pml ob1 -mca btl ^openib -mca btl_tcp_if_include 192.168.10.0/24 -mca plm_rsh_args "-p 20024" -x NCCL_IB_DISABLE=0 -x NCCL_DEBUG=VERSION -x NCCL_SOCKET_IFNAME=net1 -x NCCL_IB_HCA=mlx5_2,mlx5_8 -x UCX_NET_DEVICES=net1 -x NCCL_NET_GDR_READ=1 all_reduce_perf -b 8 -e 16G -f2 -g 2
# nThread 1 nGpus 2 minBytes 8 maxBytes 17179869184 step: 2(factor) warmup iters: 5 iters: 20 agg iters: 1 validation: 1 graph: 0
#
# Using devices
#  Rank  0 Group  0 Pid  11142 on nvidiatools-29-workload device  0 [0000:61:00] NVIDIA L40S
#  Rank  1 Group  0 Pid  11142 on nvidiatools-29-workload device  1 [0000:e1:00] NVIDIA L40S
#  Rank  2 Group  0 Pid  11317 on nvidiatools-30-workload device  0 [0000:61:00] NVIDIA L40S
#  Rank  3 Group  0 Pid  11317 on nvidiatools-30-workload device  1 [0000:e1:00] NVIDIA L40S
#
# Reducing maxBytes to 15534478677 due to memory limitation
NCCL version 2.27.3+cuda12.9
#
#                                                              out-of-place                       in-place          
#       size         count      type   redop    root     time   algbw   busbw #wrong     time   algbw   busbw #wrong
#        (B)    (elements)                               (us)  (GB/s)  (GB/s)            (us)  (GB/s)  (GB/s)       
           8             2     float     sum      -1    17.10    0.00    0.00      0    17.11    0.00    0.00      0
          16             4     float     sum      -1    16.79    0.00    0.00      0    17.07    0.00    0.00      0
          32             8     float     sum      -1    18.78    0.00    0.00      0    18.69    0.00    0.00      0
          64            16     float     sum      -1    19.40    0.00    0.00      0    19.54    0.00    0.00      0
         128            32     float     sum      -1    19.57    0.01    0.01      0    19.92    0.01    0.01      0
         256            64     float     sum      -1    20.08    0.01    0.02      0    20.15    0.01    0.02      0
         512           128     float     sum      -1    20.38    0.03    0.04      0    20.65    0.02    0.04      0
        1024           256     float     sum      -1    20.75    0.05    0.07      0    20.60    0.05    0.07      0
        2048           512     float     sum      -1    21.20    0.10    0.14      0    20.81    0.10    0.15      0
        4096          1024     float     sum      -1    22.02    0.19    0.28      0    21.66    0.19    0.28      0
        8192          2048     float     sum      -1    23.37    0.35    0.53      0    23.16    0.35    0.53      0
       16384          4096     float     sum      -1    25.28    0.65    0.97      0    25.11    0.65    0.98      0
       32768          8192     float     sum      -1    28.34    1.16    1.73      0    28.50    1.15    1.72      0
       65536         16384     float     sum      -1    34.84    1.88    2.82      0    35.16    1.86    2.80      0
      131072         32768     float     sum      -1    50.01    2.62    3.93      0    49.83    2.63    3.95      0
      262144         65536     float     sum      -1    88.46    2.96    4.45      0    87.70    2.99    4.48      0
      524288        131072     float     sum      -1    170.7    3.07    4.61      0    169.8    3.09    4.63      0
     1048576        262144     float     sum      -1    334.5    3.13    4.70      0    333.4    3.15    4.72      0
     2097152        524288     float     sum      -1    371.8    5.64    8.46      0    371.6    5.64    8.47      0
     4194304       1048576     float     sum      -1    702.4    5.97    8.96      0    701.5    5.98    8.97      0
     8388608       2097152     float     sum      -1   1350.9    6.21    9.31      0   1352.6    6.20    9.30      0
    16777216       4194304     float     sum      -1   2622.3    6.40    9.60      0   2624.8    6.39    9.59      0
    33554432       8388608     float     sum      -1   5250.9    6.39    9.59      0   5262.6    6.38    9.56      0
    67108864      16777216     float     sum      -1    10496    6.39    9.59      0    10519    6.38    9.57      0
   134217728      33554432     float     sum      -1    21010    6.39    9.58      0    20996    6.39    9.59      0
   268435456      67108864     float     sum      -1    42017    6.39    9.58      0    42036    6.39    9.58      0
   536870912     134217728     float     sum      -1    84016    6.39    9.59      0    83880    6.40    9.60      0
  1073741824     268435456     float     sum      -1   167668    6.40    9.61      0   168001    6.39    9.59      0
  2147483648     536870912     float     sum      -1   335268    6.41    9.61      0   335296    6.40    9.61      0
  4294967296    1073741824     float     sum      -1   670576    6.40    9.61      0   670652    6.40    9.61      0
  8589934592    2147483648     float     sum      -1  1338003    6.42    9.63      0  1340024    6.41    9.62      0
# Out of bounds values : 0 OK
# Avg bus bandwidth    : 4.74277 
#
~~~
