#!/bin/bash

:<<EOF
get all image :  cilium connectivity test --print-image-artifacts

https://docs.cilium.io/en/latest/operations/troubleshooting/#cilium-connectivity-tests

它在 cilium-test namespace 下创建一些测试容器 
    (1) Pod-to-pod (intra-host)
    (2) Pod-to-pod (inter-host)
    (3) Pod-to-service (intra-host)
    (4) Pod-to-service (inter-host) , 覆盖 VXLAN overlay port if used
    (5) Pod-to-external resource ， 覆盖 Egress, CiliumNetworkPolicy, masquerade

EOF

set -o errexit
set -o nounset
set -o pipefail

function GetProxyImage(){
    HELP_MSG=$( cilium connectivity test -h )
    IMAGE_CURL=$( echo "$HELP_MSG" | grep "curl-image" | grep -oE "quay.io/.*@" | tr -d '@' )
    IMAGE_DNS=$( echo "$HELP_MSG" | grep "dns-test-server-image" | grep -oE "docker.io/.*@" | tr -d '@' )
    IMAGE_FRR=$( echo "$HELP_MSG" | grep "frr-image" | grep -oE "quay.io/.*@" | tr -d '@' )
    IMAGE_JSON=$( echo "$HELP_MSG" | grep "json-mock-image" | grep -oE "quay.io/.*@" | tr -d '@' )
    IMAGE_SOCAT=$( echo "$HELP_MSG" | grep "socat-image" | grep -oE "docker.io/.*@" | tr -d '@' )
    IMAGE_DISRUPT=$( echo "$HELP_MSG" | grep "test-conn-disrupt-image" | grep -oE "quay.io/.*@" | tr -d '@' )

    [ -n "${IMAGE_CURL}" ] || { echo "error, did not find curl image"  ; cilium connectivity test -h  ; exit 1 ; }
    [ -n "${IMAGE_DNS}" ] || { echo "error, did not find dns image"  ; cilium connectivity test -h  ; exit 1 ; }
    [ -n "${IMAGE_FRR}" ] || { echo "error, did not find frr image"  ; cilium connectivity test -h  ; exit 1 ; }
    [ -n "${IMAGE_JSON}" ] || { echo "error, did not find json image"  ; cilium connectivity test -h  ; exit 1 ; }
    [ -n "${IMAGE_SOCAT}" ] || { echo "error, did not find socat image"  ; cilium connectivity test -h  ; exit 1 ; }
    [ -n "${IMAGE_DISRUPT}" ] || { echo "error, did not find disrupt image"  ; cilium connectivity test -h  ; exit 1 ; }


    IMAGE_CURL=$( echo "${IMAGE_CURL}" | sed 's/quay.io/quay.m.daocloud.io/' )
    IMAGE_DNS=$( echo "${IMAGE_DNS}" | sed 's/docker.io/docker.m.daocloud.io/' )
    IMAGE_FRR=$( echo "${IMAGE_FRR}" | sed 's/quay.io/quay.m.daocloud.io/' )
    IMAGE_JSON=$( echo "${IMAGE_JSON}" | sed 's/quay.io/quay.m.daocloud.io/' )
    IMAGE_SOCAT=$( echo "${IMAGE_SOCAT}" | sed 's/docker.io/docker.m.daocloud.io/' )
    IMAGE_DISRUPT=$( echo "${IMAGE_DISRUPT}" | sed 's/quay.io/quay.m.daocloud.io/' )

}
GetProxyImage

set -x

cilium connectivity test \
    --curl-image ${IMAGE_CURL} \
    --dns-test-server-image ${IMAGE_DNS} \
    --frr-image ${IMAGE_FRR} \
    --json-mock-image ${IMAGE_JSON} \
    --socat-image ${IMAGE_SOCAT} \
    --test-conn-disrupt-image ${IMAGE_DISRUPT} \
    --external-cidr  "1.0.0.0/8" \
    --external-ip    "111.124.203.38" \
    --external-target   "www.126.com" \
    $@


    --external-other-ip  "180.101.49.44" \
