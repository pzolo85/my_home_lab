# k8s notes 

I initially thought of using the guide just as a reference, and set things up similarly.. but after I started I decided it's better to follow step-by-step the first time.
Then I can try again and set-up a control plane on HA. 

## VM set-up 
- 4 VM including 1 jump box 1 control plane nodes and 2 worker nodes.
```bash
for VM_NAME in jumpbox server node-0 node-1 ; do VM_NAME=${VM_NAME} ./create_cloud_init.sh ; done

export VM_RAM=2048; export VM_CPU=1; export VM_DISK=20; for VM_NAME in server node-0 node-1 ; do VM_NAME=${VM_NAME} ./create_vm.sh ; done
[...]

export VM_RAM=512; export VM_CPU=1; export VM_DISK=10; VM_NAME=jumpbox ./create_vm.sh  
[...]

for d in server node-0 node-1 jumpbox ; do sudo virsh domifaddr --domain $d ; done | grep vnet
 vnet0      52:54:00:6e:37:06    ipv4         192.168.122.120/24
 vnet1      52:54:00:3b:eb:0c    ipv4         192.168.122.14/24
 vnet2      52:54:00:2d:19:69    ipv4         192.168.122.71/24
 vnet3      52:54:00:30:48:e2    ipv4         192.168.122.163/24

echo -e "192.168.122.120 server\n192.168.122.14 node-0\n192.168.122.71 node-1\n192.168.122.163 jumpbox" | sudo tee --append /etc/hosts
```

## cert auth 
- All the `openssl` commands use this [config](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/ca.conf)
```bash
root@jumpbox:~/kubernetes-the-hard-way# ls -1 *.crt
admin.crt		    	            <-- CN = admin, O = system:masters 
ca.crt				                <-- C = US, ST = Washington, L = Seattle, CN = CA
kube-api-server.crt		        <-- CN = kubernetes, C = US, ST = Washington, L = Seattle # uses SAN IP 10.23.0.1 DNS:kubernetes 
kube-controller-manager.crt   <-- CN = system:kube-controller-manager, O = system:kube-controller-manager, C = US, ST = Washington, L = Seattle
kube-proxy.crt			          <-- CN = system:kube-proxy, O = system:node-proxier, C = US, ST = Washington, L = Seattle
kube-scheduler.crt		        <-- CN = system:kube-scheduler, O = system:system:kube-scheduler, C = US, ST = Washington, L = Seattle
node-0.crt			              <-- CN = system:node:node-0, O = system:nodes, C = US, ST = Washington, L = Seattle # The CN needs to match the node name
node-1.crt
service-accounts.crt		      <-- CN = service-accounts
```
- Every cert is signed by the local CA. 
- The `node-[0|1].[crt|key]` is placed on `/var/lib/kubelet/kubelet.[crt|key]` on each `node`. 
- The `ca.[key|crt]` `kube-api-server[key|crt]` and `service-accounts.[crt|key]` files are placed on the `server`.
- The rest of the keys are used to generate client auth config. 

## kubconfig 
- Generated using `kubectl` with set-cluster, set-credentials and set-context 
```bash
root@jumpbox:~/kubernetes-the-hard-way# ls -l *.kubeconfig
-rw------- 1 root root  9953 Jul 10 14:35 admin.kubeconfig
-rw------- 1 root root 10305 Jul 10 14:35 kube-controller-manager.kubeconfig
-rw------- 1 root root 10183 Jul 10 14:32 kube-proxy.kubeconfig
-rw------- 1 root root 10231 Jul 10 14:35 kube-scheduler.kubeconfig
-rw------- 1 root root 10161 Jul 10 14:32 node-0.kubeconfig
-rw------- 1 root root 10161 Jul 10 14:32 node-1.kubeconfig
```
- The nodes get their respective kubconfig file plus the kube-proxy 
```bash
root@jumpbox:~/kubernetes-the-hard-way# ssh node-0 tree /var/lib/k*
/var/lib/kube-proxy
└── kubeconfig
/var/lib/kubelet
├── ca.crt
├── kubeconfig
├── kubelet.crt
└── kubelet.key
```
- The server gets the admin, kube-controller-manager and the kube-scheduler 

## Encryption 
- this explains how to encrypt objects before writting them to etcd https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/
- we generate a 32 bytes key and use it on this template 
```
root@jumpbox:~/kubernetes-the-hard-way# cat configs/encryption-config.yaml 
kind: EncryptionConfiguration
apiVersion: apiserver.config.k8s.io/v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
```
- the file is placed on the `server`

## etcd 
- runs on the `server` https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/07-bootstrapping-etcd.md
```bash
root@server:~# cat /etc/systemd/system/etcd.service 
[...]
Type=notify
ExecStart=/usr/local/bin/etcd \
  --name controller \
  --initial-advertise-peer-urls http://127.0.0.1:2380 \
  --listen-peer-urls http://127.0.0.1:2380 \
  --listen-client-urls http://127.0.0.1:2379 \
  --advertise-client-urls http://127.0.0.1:2379 \
  --initial-cluster-token etcd-cluster-0 \
  --initial-cluster controller=http://127.0.0.1:2380 \
  --initial-cluster-state new \
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5
[...]
```

## k8s control plane 
- The control plane runs initially the api-server, the scheduler and the controller manager.
```bash
root@server:~# tree /etc/ku* /var/lib/k* /etc/systemd/system/k*
/etc/kubernetes
└── config
    └── kube-scheduler.yaml
/var/lib/kubernetes
├── ca.crt
├── ca.key
├── encryption-config.yaml
├── kube-api-server.crt
├── kube-api-server.key
├── kube-controller-manager.kubeconfig
├── kube-scheduler.kubeconfig
├── service-accounts.crt
└── service-accounts.key
/etc/systemd/system/kube-apiserver.service  [error opening dir]
/etc/systemd/system/kube-controller-manager.service  [error opening dir]
/etc/systemd/system/kube-scheduler.service  [error opening dir]
```
- Once all services are started, we can query the `kube-api-server`.
```
root@server:~# kubectl cluster-info dump --kubeconfig admin.kubeconfig | jq .kind  -r
NodeList
EventList
ReplicationControllerList
ServiceList
DaemonSetList
DeploymentList
ReplicaSetList
PodList
EventList
ReplicationControllerList
ServiceList
DaemonSetList
DeploymentList
ReplicaSetList
PodList
```

## Control Plane to worker communication
- RBAC is required between control plane and worker (kubelet api) in order to collect stats and run remote commands. 
```bash
root@server:~# kubectl apply -f kube-apiserver-to-kubelet.yaml --kubeconfig admin.kubeconfig
clusterrole.rbac.authorization.k8s.io/system:kube-apiserver-to-kubelet created
clusterrolebinding.rbac.authorization.k8s.io/system:kube-apiserver created
```
- The cluster role specifies what API and resources you have access to. The binding binds the role to user kubernetes
```bash
root@server:~# kubectl --kubeconfig admin.kubeconfig get clusterrole system:kube-apiserver-to-kubelet -o json  | jq .rules
[
  {
    "apiGroups": [
      ""
    ],
    "resources": [
      "nodes/proxy",
      "nodes/stats",
      "nodes/log",
      "nodes/spec",
      "nodes/metrics"
    ],
    "verbs": [
      "*"
    ]
  }
]
root@server:~# kubectl --kubeconfig admin.kubeconfig get clusterrolebindings.rbac.authorization.k8s.io system:kube-apiserver -o json | jq '{ref:.roleRef,sub:.subjects}'
[...]
  "ref": {
    "apiGroup": "rbac.authorization.k8s.io",
    "kind": "ClusterRole",
    "name": "system:kube-apiserver-to-kubelet"
  },
  "sub": [
    {
      "apiGroup": "rbac.authorization.k8s.io",
      "kind": "User",
      "name": "kubernetes"
    }
[...]
```
- The kubernetes user is the api-server: 
```bash
root@jumpbox:~/kubernetes-the-hard-way# openssl x509 -in kube-api-server.crt  -text  -noout | grep kuberne
        Subject: CN = kubernetes, C = US, ST = Washington, L = Seattle
                IP Address:127.0.0.1, IP Address:10.32.0.1, DNS:kubernetes, DNS:kubernetes.default, DNS:kubernetes.default.svc, DNS:kubernetes.default.svc.cluster, DNS:kubernetes.svc.cluster.local, DNS:server.kubernetes.local, DNS:api-server.kubernetes.local
```

## Worker nodes 
- The following config for cni is copied over to the worker nodes.
- CNI plugin job is to give IP addresses to pods via IPAM 
- `kube-proxy` job is to manage virtual service cluster IP (used by services) and link them to a cidr IP (used in pods) via iptabes.
```bash
root@jumpbox:~/kubernetes-the-hard-way# cat 10-bridge.conf  | jq
{
  "cniVersion": "1.0.0",
  "name": "bridge",
  "type": "bridge",
  "bridge": "cni0",
  "isGateway": true,
  "ipMasq": true,
  "ipam": 
    {
    "type": "host-local",
    "ranges": [
      [
        {
          "subnet": "10.200.1.0/24"
        }
      ]
    ],
    "routes": [
      {
        "dst": "0.0.0.0/0"
      }
    ]
  }
}

root@jumpbox:~/kubernetes-the-hard-way# cat configs/99-loopback.conf | jq 
{
  "cniVersion": "1.1.0",
  "name": "lo",
  "type": "loopback"
}

root@jumpbox:~/kubernetes-the-hard-way# cat configs/kube-proxy-config.yaml  | yq 
{
  "kind": "KubeProxyConfiguration",
  "apiVersion": "kubeproxy.config.k8s.io/v1alpha1",
  "clientConnection": 
  {
    "kubeconfig": "/var/lib/kube-proxy/kubeconfig"
  },
  "mode": "iptables",
  "clusterCIDR": "10.200.0.0/16"
}
```
- The kubelet is configued to talk to `kube-api-server` via webhook for authorization
- Authentication is done via CA certs
- The kubelet knows how to register to the `server` by using the `kubeconfig`
- The kubelet config specifies the container runtime endpoint used to create pods. 
```bash
root@node-1:~# cat /var/lib/kubelet/kubelet-config.yaml | yq 
{
  "kind": "KubeletConfiguration",
  "apiVersion": "kubelet.config.k8s.io/v1beta1",
  "address": "0.0.0.0",
  "authentication": {
    "anonymous": {
      "enabled": false
    },
    "webhook": {
      "enabled": true
    },
    "x509": {
      "clientCAFile": "/var/lib/kubelet/ca.crt"
    }
  },
  "authorization": {
    "mode": "Webhook"
  },
  "cgroupDriver": "systemd",
  "containerRuntimeEndpoint": "unix:///var/run/containerd/containerd.sock",
  "enableServer": true,
  "failSwapOn": false,
  "maxPods": 16,
  "memorySwap": {
    "swapBehavior": "NoSwap"
  },
  "port": 10250,
  "resolvConf": "/etc/resolv.conf",
  "registerNode": true,
  "runtimeRequestTimeout": "15m",
  "tlsCertFile": "/var/lib/kubelet/kubelet.crt",
  "tlsPrivateKeyFile": "/var/lib/kubelet/kubelet.key"
}

root@node-1:~# cat /etc/systemd/system/kubelet.service 
[...]
ExecStart=/usr/local/bin/kubelet \
  --config=/var/lib/kubelet/kubelet-config.yaml \
  --kubeconfig=/var/lib/kubelet/kubeconfig \
  --v=2
[...]
```