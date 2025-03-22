#!/bin/bash

: <<EOF

实现：
    1 不同集群间的 pod ip 相互访问  Pod IP  （ ipv4 和 ipv6 ）

    2 不同集群间，可以访问 对方的 service cluster ip  ， 实现跨集群访问服务
       不同集群的 pod 也可以 共享一个 service， 实现服务的跨集群 高可用
    甚至，包括 场景 split a service’s pods into e.g. two groups, with the first half scheduled to cluster1, and the second half to cluster2，If you have scattered your pods of a same service into different clusters , and you would like service discovery/load-balancing or enforce network policies on these services, you may need clustermesh.

    3 跨集群间的 服务发现 Transparent service discovery with standard Kubernetes services and coredns/kube-dns.

    4 不同集群间的网络policy（只支持部分类型的policy）

    5 跨集群间的流量加密Transparent encryption for all communication between nodes in the local cluster as well as across cluster boundaries.

    6 hubble 可观性 能跨集群 查看 （暂时没测试出来）

     7 它支持 enableEndpointSliceSynchronization ， 因此， ingress 应该可以实现 跨集群 转发 


https://docs.cilium.io/en/latest/network/clustermesh/clustermesh/
要求：
    （1）集群运行在 Encapsulation 后者 Native-Routing mode ( native routing 模式的集群，需要在路由器上 安装好 pod 路由 ) 
    (2) PodCIDR   and all nodes 的 子网不冲突 , clusterIP 可以重叠
    (3) 多集群间的所有 node 都要能直接互通
    (4) 集群互联 默认 最多 255 ，  通过牺牲  cluster-local identities 也可扩展到 511 个 
    (5) 不同集群的 clustermesh 的 nodePort 不能使用相同端口
        apiserver:
            service:
            type: NodePort
            # WARNING: make sure to configure a different NodePort in each cluster if
            # kube-proxy replacement is enabled, as Cilium is currently affected by a known bug (#24692) when NodePorts are handled by the KPR implementation
            nodePort: ${CLUSTERMESH_APISERVER_NODEPORT}


EOF


CURRENT_FILENAME=$( basename $0 )
CURRENT_DIR_PATH=$(cd $(dirname $0); pwd)

#install crd for enableMCSAPISupport
# serviceimports.multicluster.x-k8s.io\


CONFIG_DIR=${CONFIG_DIR:-"/root/clustermesh"}
mkdir -p ${CONFIG_DIR} || true

function GenerateKubeConfig(){
    
    cd ${CONFIG_DIR}
    rm * -rf

    echo "get kubeconfig from all clusters"
    scp root@172.16.1.11:/root/.kube/config ./cluster1
    scp root@172.16.2.22:/root/.kube/config ./cluster2

    echo "generate a merged kubeconfig"

cat <<EOF > config
apiVersion: v1
clusters:
- cluster:
$( grep "certificate-authority-data" ./cluster1 )
$( grep "server:" ./cluster1 )
  name: cluster1
- cluster:
$( grep "certificate-authority-data" ./cluster2 )
$( grep "server:" ./cluster2 )
  name: cluster2
contexts:
- context:
    cluster: cluster1
    user: cluster1-admin
  name: cluster1
- context:
    cluster: cluster2
    user: cluster2-admin
  name: cluster2
current-context: cluster2
kind: Config
preferences: {}
users:
- name: cluster1-admin
  user:
$( grep "client-certificate-data" ./cluster1 )
$( grep "client-key-data" ./cluster1 )
- name: cluster2-admin
  user:
$( grep "client-certificate-data" ./cluster2 )
$( grep "client-key-data" ./cluster2 )
EOF

    export KUBECONFIG=/root/clustermesh/config

    (
        echo "check cluster1"
        kubectl config use-context cluster1
        kubectl get pod 

        echo "check cluster2"
        kubectl config use-context cluster2
        kubectl get pod 
    )
}

GenerateKubeConfig

# 把 cluster1 的证书 传播给 其它所有的集群 ，共享一份
echo "--------- share a certificate authority (CA) between the clusters , copy CA tls to "
kubectl --context cluster2 delete secret -n kube-system cilium-ca || true
kubectl --context=cluster1 get secret -n kube-system cilium-ca -o yaml | kubectl --context cluster2 apply -f -

echo ""
echo "--------- enable clustermesh in cluster1 "
cilium clustermesh enable  --service-type NodePort  --context cluster1 
cilium clustermesh status --context cluster1 --wait

echo ""
echo "--------- enable clustermesh in cluster2 "
cilium clustermesh enable  --service-type NodePort  --context cluster2  
cilium clustermesh status --context cluster2 --wait

echo ""
echo "--------- connect cluster2 to cluster1 "
cilium clustermesh connect --context cluster2 --destination-context cluster1



sleep 30
echo ""
echo "--------- check clusterMesh status in cluster1 "
cilium clustermesh status --context cluster1


echo ""
echo "--------- check clusterMesh status in cluster2 "
cilium clustermesh status --context cluster2

#echo ""
#echo "----------------- check clusterMesh connectivity -----------------------------------"
#chmod +x ${CURRENT_DIR_PATH}/checkConnect.sh
#${CURRENT_DIR_PATH}/checkConnect.sh --context cluster1 --multi-cluster cluster2  || true


#echo "restart all pod , or else clusterMesh failed to connect "
#/root/common/tools/restartAllPods.sh





