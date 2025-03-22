#!/bin/bash

echo "======================= setup loadbalancer ipam =============================="
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

    echo ""
    echo "kubectl get CiliumLoadBalancerIPPool"
    kubectl get CiliumLoadBalancerIPPool

    echo ""
    echo "kubectl describe ippools/default-ipv4"
    kubectl describe ippools/default-ipv4

    echo ""
    echo "Loadbalancer IPAM 支持双栈"
    echo "任何 Loadbalancer service 就会分配到 ip 地址 "

fi 


echo ""
echo "===================== setup ARP announcement ==========================="

:<<EOF
 https://docs.cilium.io/en/latest/network/l2-announcements/
 https://docs.cilium.io/en/latest/network/lb-ipam/

为 service 的 externalIPs 和 loadBalancerIPs 进行 arp 宣告

require:
    (1) All devices on which L2 Aware LB will be announced should be enabled and included in the --devices flag
    (2) Kube Proxy replacement 
    (3) externalIPs.enabled=true Helm option must be set

limit:
    (1) The feature currently does not support IPv6/NDP

不适合生成 

bug:
  (1) 在 1.17.2 版本 发现， 访问 Loadbalancer ip 的 外部请求，当转发到 arp vip 所在节点上的 pod， 会失败, 通信中 cilium_host 接口会产生一个 reset 报文 。 
    如果转发到其它节点，可以访问

    官方也提到类似的问题 
    The feature is incompatible with the externalTrafficPolicy: Local on services 
    as it may cause service IPs to be announced on nodes without pods causing traffic drops.


EOF


echo "check status"
kubectl -n kube-system exec ds/cilium -- cilium-dbg config --all | grep -E  "EnableL2Announcements|KubeProxyReplacement|EnableExternalIPs"

echo "set default policy"

echo "set node master1 to enable arp announcement"
kubectl label node master1 cilium.io/arp=true

cat <<EOF | kubectl apply -f -
apiVersion: "cilium.io/v2alpha1"
kind: CiliumL2AnnouncementPolicy
metadata:
  name: default-arp
spec:
  # 如果不设置 serviceSelector， 则会为所有 service 服务
  #serviceSelector:
  #  matchLabels:
  #    io.kubernetes.service.namespace: kube-system
  # 设置生效 arp 的主机 
  nodeSelector:
    matchExpressions:
      - key: cilium.io/arp
        operator: Exists
  # This field is optional, if not specified all interfaces will be used
  interfaces:
  - eth1
  #- ^eth[0-9]+
  externalIPs: true
  loadBalancerIPs: true
EOF

echo ""
echo "kubectl get CiliumL2AnnouncementPolicy"
kubectl get CiliumL2AnnouncementPolicy

echo ""
echo "kubectl describe l2announcement"
kubectl describe l2announcement

# 当 service 被 lb-ipam 成功分配 vip 后， 每一个 service 的 VIP 会由 一个 node 来生效
# 通过 lease 锁 来抢主 cilium-l2announce-${service_namespace}-${service_name}
kubectl get lease -n kube-system | grep cilium-l2announce


echo ""
echo "Loadbalancer IPAM 支持 ipv4 单栈"


