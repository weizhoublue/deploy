#!/bin/bash

echo "======================= setup lb ipam =============================="
:<<EOF
 https://docs.cilium.io/en/latest/network/lb-ipam/
 cilium 自己实现了   LoadBalancer ip 的分配，不再 依赖 metallb , 再 配合 l2-announcements（arp） 和 BGP Control Plane

  supports IPv4 and/or IPv6 in SingleStack or DualStack mode

应用可以使用如下方式
        (1) 单独指定 vip 
        Don’t configure the annotation to request the first or last IP of an IP pool. They are reserved for the network and broadcast addresses respectively.
            kind: Service
            metadata:
            annotations:
                "lbipam.cilium.io/ips": "20.0.10.100,20.0.10.200"

        （2）两个 service 共享一个 vip  , 但不支持 跨租户 
        apiVersion: v1
        kind: Service
        metadata:
        annotations:
            "lbipam.cilium.io/sharing-key": "1234"
        ...
        ---
        apiVersion: v1
        kind: Service
        metadata:
        annotations:
            "lbipam.cilium.io/sharing-key": "1234"
        ...

EOF

if ! kubectl get CiliumLoadBalancerIPPool default-ipv4 > /dev/null 2>&1; then

  cat <<EOF | kubectl apply -f -
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: default-ipv4
spec:
  blocks:
  #- cidr: "10.0.10.0/24"
  - start: "172.16.1.200"
    stop: "172.16.1.220"
  # 如果不设置 serviceSelector， 则会为所有 service 服务
  #serviceSelector:
  #  matchLabels:
  #    io.kubernetes.service.namespace: kube-system
---
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: default-ipv6
spec:
  blocks:
  - start: "fd01::100"
    stop: "fd01::120"
EOF


    kubectl get CiliumLoadBalancerIPPool

    kubectl describe ippools/default-ipv4

    echo "任何 Loadbalancer service 就会分配到 ip 地址 "

fi 




echo "===================== setup bgp ==========================="

:<<EOF
https://docs.cilium.io/en/latest/network/bgp-control-plane/bgp-control-plane/
# CiliumBGPClusterConfig  CiliumBGPPeerConfig  CiliumBGPAdvertisement  CiliumBGPNodeConfigOverride
https://docs.cilium.io/en/latest/network/bgp-control-plane/bgp-control-plane-v2/
# CiliumBGPPeeringPolicy will be discontinued in future
https://docs.cilium.io/en/latest/network/bgp-control-plane/bgp-control-plane-v1/

https://docs.cilium.io/en/latest/network/bgp-control-plane/bgp-control-plane-operation/


该功能 能够向 集群外部  传播 
    (1) 每个节点的 pod cidr 子网 . Cilium BGP control plane advertises pod CIDR allocated to the node and not the entire range 
    (2) 任何的  service  ip， 包括了 clusterIP、loadbalancer 、 externalIp  .  Cilium BGP Control Plane advertises exact routes for the VIPs ( /32 or /128 prefixes ). 
        对于 externalTrafficPolicy=Local  和 internalTrafficPolicy  , 只有本地有 pod， 本地 bpg 才会 传播 其 vip 
    (3) 支持双栈 

EOF

echo "check status"
kubectl -n kube-system exec ds/cilium -- cilium-dbg config --all | grep -i bgp

K8S_BGP_ASN=${K8S_BGP_ASN:-"65001"}
BGP_ROUTER_V4IP=${BGP_ROUTER_V4IP:-"172.16.1.1/32"}
BGP_ROUTER_ASN=${BGP_ROUTER_ASN:-"65000"}


# 如下 serviceSelector 使得 整个集群的所有 service 的 loadbalancerIP 都会传播

kubectl delete CiliumBGPClusterConfig default &>/dev/null || true
cat <<EOF | kubectl apply -f -
apiVersion: cilium.io/v2
kind: CiliumBGPClusterConfig
metadata:
  name: default
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/os: linux
  bgpInstances:
  - name: "instance-65000"
    localASN: ${K8S_BGP_ASN}
    peers:
    - name: "peer-v4"
      localPort: 179
      peerASN: ${BGP_ROUTER_ASN}
      peerAddress: ${BGP_ROUTER_V4IP}
      # 指向 CiliumBGPPeerConfig
      peerConfigRef:
        name: "cilium-peer"
---
# 定义 BPG 工作的参数
apiVersion: cilium.io/v2
kind: CiliumBGPPeerConfig
metadata:
  name: cilium-peer
spec:
  transport:
    peerPort: 179
  timers:
    connectRetryTimeSeconds: 12
    holdTimeSeconds: 9
    keepAliveTimeSeconds: 3
  ebgpMultihop: 1
  gracefulRestart:
    enabled: true
    restartTimeSeconds: 15
  families:
    - afi: ipv4
      safi: unicast
      # 指向 CiliumBGPAdvertisement
      advertisements:
        matchLabels:
          advertise: "bgp"
---
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata:
  name: bgp-advertisements
  labels:
    advertise: bgp
spec:
  advertisements:
    # 传播 pod cidr
    - advertisementType: "PodCIDR"
    # 传播 service 的 ClusterIP、ExternalIP、LoadBalancerIP
    - advertisementType: "Service"
      service:
        addresses:
          - ClusterIP
          - ExternalIP
          - LoadBalancerIP
EOF


echo "displays current peering states from all nodes in the kubernetes cluster."
cilium bgp peers

echo "displays detailed information about local BGP routing table and per peer advertised routing information."
cilium bgp routes
