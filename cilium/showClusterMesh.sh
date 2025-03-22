#!/bin/bash

<<EOF
# https://docs.cilium.io/en/latest/operations/troubleshooting/#cluster-mesh-troubleshooting

注意：
(1) 不同集群的 clustermesh 的 nodePort 不能使用相同端口
  apiserver:
    service:
      type: NodePort
      # WARNING: make sure to configure a different NodePort in each cluster if
      # kube-proxy replacement is enabled, as Cilium is currently affected by a known bug (#24692) when NodePorts are handled by the KPR implementation
      nodePort: ${CLUSTERMESH_APISERVER_NODEPORT}

EOF


CILIUM_NS=${CILIUM_NS:-"kube-system"}
CONFIG_DIR=${CONFIG_DIR:-"/root/clustermesh"}


export KUBECONFIG="${CONFIG_DIR}/config"
[ -f "${CONFIG_DIR}/config" ] || { echo "kubeconfig ${KUBECONFIG} is not found"; exit 1 
cilium clustermesh status || true



echo "===================================== show clusterMesh status in cluster1 ==================================="

echo ""
echo "--------- check clusterMesh status in cluster1 "
cilium clustermesh status --context cluster1

echo ""
echo "--------- check clusterMesh status in cluster2 "
cilium clustermesh status --context cluster2


if ! hubble status &>/dev/null ; then
    cilium hubble port-forward &
    sleep 3
fi 

echo ""
echo "hubble status"
hubble status

echo ""
echo "hubble list  nodes"
hubble list  nodes



echo ""
echo "===================================== show status of each agent in cluster1 ==================================="
echo ""

kubectl config use-context cluster1
AGENT_PODS=$( kubectl get pods -n ${CILIUM_NS} -l app.kubernetes.io/name=cilium-agent | sed '1d' | awk '{ print $1}' )

for POD in ${AGENT_PODS} ; do
    echo ""
    if kubectl get pod -n ${CILIUM_NS} ${POD} | grep Running &>/dev/null ; then
        echo "-------------- agent pod ${POD} : Running "
        kubectl exec -it -n ${CILIUM_NS}  ${POD} -c cilium-agent -- cilium-dbg troubleshoot clustermesh
    else 
        echo "-------------- agent pod ${POD} : Not Running "
    fi
    echo ""
done


echo ""
echo "===================================== show status of each agent in cluster2 ==================================="
echo ""

kubectl config use-context cluster2
AGENT_PODS=$( kubectl get pods -n ${CILIUM_NS} -l app.kubernetes.io/name=cilium-agent | sed '1d' | awk '{ print $1}' )

for POD in ${AGENT_PODS} ; do
    echo ""
    if kubectl get pod -n ${CILIUM_NS} ${POD} | grep Running &>/dev/null ; then
        echo "-------------- agent pod ${POD} : Running "
        kubectl exec -it -n ${CILIUM_NS}  ${POD} -c cilium-agent -- cilium-dbg troubleshoot clustermesh
    else 
        echo "-------------- agent pod ${POD} : Not Running "
    fi
    echo ""
done


echo ""
echo "===================================== show status of clustermesh in cluster1 ==================================="
echo ""

kubectl config use-context cluster1
CLUSTERMESH_PODS=$( kubectl get -n ${CILIUM_NS} pod -l app.kubernetes.io/name=clustermesh-apiserver | sed '1d' | awk '{ print $1}' )

echo ""
kubectl get service -n kube-system clustermesh-apiserver
echo ""

for POD in ${CLUSTERMESH_PODS} ; do
    echo ""
    if kubectl get pod -n ${CILIUM_NS} ${POD} | grep Running &>/dev/null ; then
        echo "-------------- clustermesh pod ${POD} : Running "
        kubectl --context=cluster1 exec -it -n ${CILIUM_NS}  ${POD}  -c kvstoremesh -- /usr/bin/clustermesh-apiserver kvstoremesh-dbg troubleshoot
    else 
        echo "-------------- clustermesh pod ${POD} : Not Running "
    fi
    echo ""
done


echo ""
echo "===================================== show status of clustermesh in cluster2 ==================================="
echo ""

kubectl config use-context cluster2
CLUSTERMESH_PODS=$( kubectl get -n ${CILIUM_NS} pod -l app.kubernetes.io/name=clustermesh-apiserver | sed '1d' | awk '{ print $1}' )

echo ""
kubectl get service -n kube-system clustermesh-apiserver
echo ""

for POD in ${CLUSTERMESH_PODS} ; do
    echo ""
    if kubectl get pod -n ${CILIUM_NS} ${POD} | grep Running &>/dev/null ; then
        echo "-------------- clustermesh pod ${POD} : Running "
        kubectl exec -it -n ${CILIUM_NS}  ${POD}  -c kvstoremesh -- /usr/bin/clustermesh-apiserver kvstoremesh-dbg troubleshoot
    else 
        echo "-------------- clustermesh pod ${POD} : Not Running "
    fi
    echo ""
done







echo ""
echo "===================================== check clusterMesh connectivity ==================================="
# chmod +x ${CURRENT_DIR_PATH}/checkConnect.sh
# ${CURRENT_DIR_PATH}/checkConnect.sh --context cluster1 --multi-cluster cluster2  || true

