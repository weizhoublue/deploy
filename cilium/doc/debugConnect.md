测试内容
    （1） 同节点、跨节点 pod 访问
    （2） 同节点、跨节点 的 service 的 cluster ip  访问
    （3） pod 访问 集群外部 
    （4） 外部访问  nodePort 、 Loadbalancer 
    （5） 跨集群访问 pod ip 、 service cluster ip 


================================================================================================



1 通过 nodeport 31000 访问 hubble webui， 来看 pod 之间的 可观测数据 

================================================================================================

2 整个集群范围 确认数据包转发 
    开启  , 即可 使用 hubble  cli 工具
    cilium hubble port-forward &


    hubble status
    
    hubble list  nodes

    查看流量
    hubble observe
    hubble observe --port 5555
    hubble observe --pod nginx65-6d6476db4d-s5gkq
    hubble observe --from-ip=1.1.1.1

    在主机上，查看全局被丢弃的流量
    hubble observe --since 3m --verdict DROPPED --verdict ERROR  -f

================================================================================================


3 确认单节点

    进入 问题主机 agent 上 
    查看丢包
    kubectl exec -n kube-system cilium-qvxl7 -- hubble observe --since 3m --verdict DROPPED --verdict ERROR  -f
    查看正常转发
    kubectl exec -n kube-system cilium-qvxl7 -- hubble observe --since 3m  -f

    或者使用 ( 这个看到的数据 最全 ！！！！)
    kubectl exec -it -n kube-system cilium-qvxl7  -- cilium-dbg monitor --type drop
    kubectl exec -it -n kube-system cilium-qvxl7  -- cilium-dbg monitor 




================================================================================================

4 观测 L7 数据 内容
https://docs.cilium.io/en/latest/observability/visibility/
创建 CiliumNetworkPolicy  来进行监控 


#-------对 指定 pod 的 http 观测
POD_LABEL=nginx60
POD_NS=default
cat <<EOF | kubectl apply -f -
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: pod-http-visibility
  namespace: $POD_NS
spec:
  endpointSelector:
    matchLabels:
      app: $POD_LABEL
  ingress:
  - fromEntities:
    - all
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
      rules:
        http:
        - {}
  - fromEntities:
    - all
EOF

#-------对 指定 namespace 的 http 观测
NAME_SPACE=default
cat <<EOF | kubectl apply -f -
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: ns-http-visibility
  namespace: $NAME_SPACE
spec:
  endpointSelector: {}
  egress:
    - toPorts:
      - ports:
        - port: "80"
          protocol: TCP
        rules:
          http:
          - method: ".*"
    - toEndpoints:
      - {}
EOF



#-------对 集群  http 观测
NAME_SPACE=podinfo
cat <<EOF | kubectl apply -f -
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: cluster-http-visibility
spec:
  endpointSelector: {}
  egress:
    - toPorts:
      - ports:
        - port: "80"
          protocol: TCP
        rules:
          http:
          - method: ".*"
    - toEndpoints:
      - {}
EOF


#-------对 指定 pod 的 dns 观测
POD_LABEL=nginx60
POD_NS=default
cat <<EOF | kubectl apply -f -
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: pod-dns-visibility
  namespace: $POD_NS
spec:
  endpointSelector:
    matchLabels:
      app: $POD_LABEL
  egress:
    - toPorts:
      - ports:
        - port: "80"
          protocol: TCP
        rules:
          http:
          - method: ".*"
    - toEndpoints:
      - {}
EOF

#-------对 指定 namespace 的 dns 观测
NAME_SPACE=podinfo
cat <<EOF | kubectl apply -f -
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: ns-dns-visibility
  namespace: $NAME_SPACE
spec:
  endpointSelector: {}
  egress:
    - toPorts:
      - ports:
        - port: "80"
          protocol: TCP
        rules:
          http:
          - method: ".*"
    - toEndpoints:
      - {}
EOF


#-------对 集群  访问 dns 观测
NAME_SPACE=podinfo
cat <<EOF | kubectl apply -f -
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: cluster-dns-visibility
spec:
  endpointSelector: {}
  egress:
    - toEndpoints:
      - matchLabels:
          k8s:io.kubernetes.pod.namespace: kube-system
          k8s:k8s-app: kube-dns
      toPorts:
      - ports:
        - port: "53"
          protocol: ANY
        rules:
          dns:
            - matchPattern: "*"
    - toFQDNs:
      - matchPattern: "*"
    - toEndpoints:
      - {}
EOF


观测 L7 流量

    进入 cilium pod 内 ， cilium monitor
        #cilium monitor -v --type l7
            Listening for events on 8 CPUs with 64x4096 of shared memory
            Press Ctrl-C to quit
            <- Request http from 0 ([k8s:run=debug k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=default k8s:io.cilium.k8s.policy.cluster=shanghai k8s:io.cilium.k8s.policy.serviceaccount=default k8s:io.kubernetes.pod.namespace=default]) to 2313 ([k8s:app=nginx65 k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=default k8s:io.cilium.k8s.policy.cluster=shanghai k8s:io.cilium.k8s.policy.serviceaccount=default k8s:io.kubernetes.pod.namespace=default]), identity 658195->680287, verdict Forwarded GET http://172.110.1.100/ => 0
            <- Response http to 0 ([k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=default k8s:io.cilium.k8s.policy.cluster=shanghai k8s:io.cilium.k8s.policy.serviceaccount=default k8s:io.kubernetes.pod.namespace=default k8s:run=debug]) from 2313 ([k8s:app=nginx65 k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=default k8s:io.cilium.k8s.policy.cluster=shanghai k8s:io.cilium.k8s.policy.serviceaccount=default k8s:io.kubernetes.pod.namespace=default]), identity 658195->680287, verdict Forwarded GET http://172.110.1.100/ => 200


