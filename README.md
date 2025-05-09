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
- [Validate The Container](#validate-the-container)

## Building The Container

The first step is to make a nvidia-tools directory.

~~~bash
$ mkdir -p ~/nvidia-tools
$ cd nvidia-tools
~~~

~~~bash

~~~

~~~bash

~~~

~~~bash
podman build . -f dockerfile.tools -t quay.io/redhat_emp1/ecosys-nvidia/nvidia-tools:0.0.1
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
