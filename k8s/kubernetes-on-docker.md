在docker上部署Kubernetes
=======================

# 1、准备
```
docker pull 172.18.26.2:5000/coreos-quay.io/coreos/hyperkube:v1.4.6_coreos.0_coreos.0
docker pull 172.18.26.2:5000/coreos-flannel:v0.6.2
docker pull 172.18.26.2:5000/coreos-etcd:v3.0.15
docker pull 172.18.26.2:5000/mritd-kubernetes-dashboard-amd64:v1.4.2
docker pull 172.18.26.2:5000/mritd-pause-amd64:3.0

docker tag 172.18.26.2:5000/coreos-quay.io/coreos/hyperkube:v1.4.6_coreos.0_coreos.0 quay.io/coreos/hyperkube:v1.4.6_coreos.0
docker tag 172.18.26.2:5000/coreos-flannel:v0.6.2 flannel:v0.6.2
docker tag 172.18.26.2:5000/coreos-etcd:v3.0.15 etcd:v3.0.15
docker tag 172.18.26.2:5000/mritd-kubernetes-dashboard-amd64:v1.4.2 gcr.io/google_containers/kubernetes-dashboard-amd64:v1.4.2
docker tag 172.18.26.2:5000/mritd-pause-amd64:3.0 gcr.io/google_containers/pause-amd64:3.0
```

# 2、Etcd

## 2.1 one node
```
docker run -d -p 2379:2379 -p 2380:2380 -p 4001:4001 \
--name etcd --restart always quay.io/coreos/etcd:v3.0.15 \
/usr/local/bin/etcd  --data-dir=data.etcd --name etcd \
--advertise-client-urls http://0.0.0.0:2379,http://0.0.0.0:4001 \
--listen-client-urls http://0.0.0.0:2379,http://0.0.0.0:4001 \
--listen-peer-urls http://0.0.0.0:2380

docker exec etcd /usr/local/bin/etcdctl set /coreos.com/network/config '{ "Network": "10.1.0.0/16" }'
docker exec etcd /usr/local/bin/etcdctl get /coreos.com/network/config
```

## 2.2 many nodes
## etcd1
```
docker run -d --net=host --name etcd --restart always quay.io/coreos/etcd:v3.0.15 \
/usr/local/bin/etcd  --data-dir=data.etcd --name etcd1 \
--initial-advertise-peer-urls http://172.18.26.1:2380 \
--listen-peer-urls http://0.0.0.0:2380 \
--advertise-client-urls http://0.0.0.0:2379,http://0.0.0.0:4001 \
--listen-client-urls http://0.0.0.0:2379,http://0.0.0.0:4001 \
--initial-cluster etcd1=http://172.18.26.1:2380,etcd2=http://172.18.26.2:2380,etcd3=http://172.18.26.3:2380 \
--initial-cluster-state new \
--initial-cluster-token my-etcd-token
```
```
docker exec etcd /usr/local/bin/etcdctl set /coreos.com/network/config '{ "Network": "10.1.0.0/16" }'
```

## etcd2
```
docker run -d --net=host --name etcd --restart always quay.io/coreos/etcd:v3.0.15 \
/usr/local/bin/etcd  --data-dir=data.etcd --name etcd2 \
--initial-advertise-peer-urls http://172.18.26.2:2380 \
--listen-peer-urls http://0.0.0.0:2380 \
--advertise-client-urls http://0.0.0.0:2379,http://0.0.0.0:4001 \
--listen-client-urls http://0.0.0.0:2379,http://0.0.0.0:4001 \
--initial-cluster etcd1=http://172.18.26.1:2380,etcd2=http://172.18.26.2:2380,etcd3=http://172.18.26.3:2380 \
--initial-cluster-state new \
--initial-cluster-token my-etcd-token
```
```
docker exec etcd /usr/local/bin/etcdctl get /coreos.com/network/config
```

## etcd3
```
docker run -d --net=host --name etcd --restart always quay.io/coreos/etcd:v3.0.15 \
/usr/local/bin/etcd  --data-dir=data.etcd --name etcd3 \
--initial-advertise-peer-urls http://172.18.26.3:2380 \
--listen-peer-urls http://0.0.0.0:2380 \
--advertise-client-urls http://0.0.0.0:2379,http://0.0.0.0:4001 \
--listen-client-urls http://0.0.0.0:2379,http://0.0.0.0:4001 \
--initial-cluster etcd1=http://172.18.26.1:2380,etcd2=http://172.18.26.2:2380,etcd3=http://172.18.26.3:2380 \
--initial-cluster-state new \
--initial-cluster-token my-etcd-token
```
```
docker exec etcd /usr/local/bin/etcdctl get /coreos.com/network/config
```

# 3、flannel
## 3.1 net1
```
docker run -d --net=host --privileged --name flannel --restart always \
-v /dev/net:/dev/net quay.io/coreos/flannel:v0.6.2 \
/opt/bin/flanneld \
--ip-masq=true \
--iface=ens160 \
--etcd-endpoints=http://172.18.26.3:4001,http://172.18.26.1:4001,http://172.18.26.2:4001
```
```
docker exec flannel cat /run/flannel/subnet.env
```
> 输出结果：  
FLANNEL_NETWORK=10.1.0.0/16  
FLANNEL_SUBNET=10.1.70.1/24  
FLANNEL_MTU=1472  
FLANNEL_IPMASQ=true

```
vi /usr/lib/systemd/system/docker.service
vi /lib/systemd/system/docker.service
```

> 修改这一行  
ExecStart=/usr/bin/dockerd --bip=10.1.37.1/24 --mtu=1472

```
systemctl daemon-reload
systemctl restart docker
ip -4 a|grep inet
```
> 输出结果：  
inet 127.0.0.1/8 scope host lo  
inet 172.18.26.70/24 brd 172.18.26.755 scope global ens160  
inet 172.19.0.1/16 scope global docker_gwbridge  
inet 10.1.37.1/24 scope global docker0  
inet 10.1.37.0/16 scope global flannel0  

## 3.2 net2
```
docker run -d --net=host --privileged \
-v /dev/net:/dev/net \
--name flannel --restart always quay.io/coreos/flannel:0.6.1 \
/opt/bin/flanneld \
--ip-masq=true \
--iface=ens160 \
--etcd-endpoints=http://172.18.26.3:4001,http://172.18.26.1:4001,http://172.18.26.2:4001
```
## 3.3 net3
```
docker run -d --net=host --privileged \
-v /dev/net:/dev/net \
--name flannel --restart always quay.io/coreos/flannel:0.6.1 \
/opt/bin/flanneld \
--ip-masq=true \
--iface=ens160 \
--etcd-endpoints=http://172.18.26.3:4001,http://172.18.26.1:4001,http://172.18.26.2:4001
```
## 3.4 test
启动一个容器
```
docker run -ti alpine sh
```
获得容器的IP
```
ip -4 a|grep inet
```
在三个节点上，使用ping命令，测试一下：容器到容器，容器到虚拟机，虚拟机到容器。 

# 4、Kubernetes

## 4.1 apiserver

### 4.1.1 账户密码

账户密码配置文件
```
# 格式：密码,用户名,用户ID
echo 123456,admin,0  > basic_auth.csv
echo 123456,chencai,1  >> basic_auth.csv
echo 123456,jichengjin,2  >> basic_auth.csv
cat basic_auth.csv
```

ABAC模式配置文件
```
echo '{"user":"admin"}'  > abac.csv
echo '{"user":"chencai","ns":"default"}' >> abac.csv
echo '{"user":"jichengjin","ns":"agileDev"}' >> abac.csv
cat abac.csv
```

### 4.1.2 双向认证

生成证书

```
mkdir -p /root/ca-certificates
cd /root/ca-certificates
```
```
openssl genrsa -out ca.key 2048
openssl req -x509 -new -nodes -key ca.key -subj "/CN=c.io" -days 10000 -out ca.crt
openssl genrsa -out server.key 2048
openssl req -new -key server.key -subj "/CN=192.168.61.130" -out server.csr
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 10000
```
```
chmod -R 777 /root/ca-certificates/*  
chown root:root /root/ca-certificates/*
```
启动api-server
```
docker run -d --net=host --name kube-apiserver --restart always \
-v /root/ca-certificates:/var/run/kubernetes quay.io/coreos/hyperkube:v1.4.6_coreos.0 \
/hyperkube \
apiserver \
--etcd-servers=http://172.18.26.1:4001,http://172.18.26.2:4001,http://172.18.26.3:4001 \
--allow-privileged=true \
--profiling=true \
--insecure_bind_address=0.0.0.0 \
--insecure_port=8080 \
--bind-address=0.0.0.0 \
--secure-port=8443 \
--service-cluster-ip-range=10.2.0.0/16 \
--service-node-port-range=0-65535 \
--basic-auth-file=/var/run/kubernetes/basic_auth.csv \
--authorization_mode=ABAC \
--authorization_policy_file=abac.csv \
--tls-cert-file=/var/run/kubernetes/server.crt \
--tls-private-key-file=/var/run/kubernetes/server.key \
--client-ca-file=/var/run/kubernetes/ca.crt 
```

### 4.1.3 简单认证

`/root/ca-certificates`内不存放证书文件。

```
docker run -d --net=host --name kube-apiserver --restart always \
-v /root/ca-certificates:/var/run/kubernetes quay.io/coreos/hyperkube:v1.4.6_coreos.0 \
/hyperkube \
apiserver \
--etcd-servers=http://172.18.26.1:4001,http://172.18.26.2:4001,http://172.18.26.3:4001 \
--allow-privileged=true \
--profiling=true \
--insecure_bind_address=0.0.0.0 \
--insecure_port=8080 \
--bind-address=0.0.0.0 \
--secure-port=8443 \
--service-cluster-ip-range=10.2.0.0/16 \
--service-node-port-range=0-65535 \
--basic-auth-file=/var/run/kubernetes/basic_auth.csv \
--authorization_mode=ABAC \
--authorization_policy_file=/var/run/kubernetes/abac.csv

docker logs kube-apiserver
```

```
docker run -d --net=host --name kube-apiserver --restart always \
-v /root/ca-certificates:/var/run/kubernetes quay.io/coreos/hyperkube:v1.4.6_coreos.0 \
/hyperkube \
apiserver \
--etcd-servers=http://172.18.26.1:4001,http://172.18.26.2:4001,http://172.18.26.3:4001 \
--insecure_bind_address=0.0.0.0 \
--service-cluster-ip-range=10.2.0.0/16

docker logs kube-apiserver
```

## 4.2 controller
```
docker run -d --net=host \
-v /root/ca-certificates:/var/run/kubernetes \
--name kube-controller --restart always quay.io/coreos/hyperkube:v1.4.6_coreos.0 \
/hyperkube \
controller-manager \
--address=0.0.0.0 \
--master=http://172.18.26.2:8080

docker logs kube-controller
```

## 4.3 scheduler
```
docker run -d --net=host \
-v /root/ca-certificates:/var/run/kubernetes \
--name kube-scheduler --restart always quay.io/coreos/hyperkube:v1.4.6_coreos.0 \
/hyperkube \
scheduler \
--address=0.0.0.0 \
--master=http://172.18.26.2:8080

docker logs kube-scheduler
```

## 4.4 kubelet
```
docker run -d \
-v /:/rootfs:ro \
-v /sys:/sys:ro \
-v /dev:/dev \
-v /var/run/docker.sock:/var/run/docker.sock \
-v /var/lib/docker/:/var/lib/docker:rw \
-v /var/lib/kubelet/:/var/lib/kubelet:rw \
-v /var/run:/var/run:rw \
--net=host \
--privileged=true \
--name kube-kubelet \
--restart always \
quay.io/coreos/hyperkube:v1.4.6_coreos.0 \
/hyperkube \
kubelet \
--allow-privileged=true \
--containerized=true \
--enable_server=true \
--api_servers=http://172.18.26.3:8080 \
--address=0.0.0.0 \
--hostname_override=172.18.26.13 \
--maximum-dead-containers=0 \
--cluster-dns=10.0.0.10 \
--cluster-domain=cluster.local

docker logs kube-kubelet
```

## 4.5 proxy

所有节点必须安装

```
docker run -d --net=host --privileged=true --name kube-proxy --restart always \
quay.io/coreos/hyperkube:v1.4.6_coreos.0 /hyperkube proxy \
--master=http://172.18.26.3:8080

docker logs kube-proxy
```

## 4.6 kubectl
```
wget http://storage.googleapis.com/kubernetes-release/release/v1.4.6/bin/linux/amd64/kubectl
chmod +x kubectl
mv kubectl /usr/local/bin/kubectl
kubectl config set-cluster default-cluster --server=http://172.18.26.3:8080
kubectl config set-context default-system --cluster=default-cluster --user=default-admin
kubectl config use-context default-system
kubectl get nodes
NAME          STATUS     AGE
172.18.26.2   Ready      5m
172.18.26.3   Ready      5m
172.18.26.4   Ready      5m
```

# 5、kubernetes-dashboard

```
docker pull siriuszg/kubernetes-dashboard-amd64
docker tag siriuszg/kubernetes-dashboard-amd64:v1.5.0 gcr.io/google_containers/kubernetes-dashboard-amd64:v1.5.0
```

给各个worker节点设置`label`
```
kubectl label node 172.18.26.4 usecase=worker
kubectl label node 172.18.26.5 usecase=worker
kubectl label node 172.18.26.6 usecase=worker
kubectl label node 172.18.26.11 usecase=storage
kubectl label node 172.18.26.12 usecase=storage
kubectl label node 172.18.26.13 usecase=fileshare
```

```
wget https://rawgit.com/kubernetes/dashboard/master/src/deploy/kubernetes-dashboard.yaml
```
阅读这一段
```
args:
# Uncomment the following line to manually specify Kubernetes API server Host
# If not specified, Dashboard will attempt to auto discover the API server and connect
# to it. Uncomment only if the default does not work.
# - --apiserver-host=http://my-address:port
```

所以，取消注释并调整为
```
- --apiserver-host=http://172.18.24.108:8080
```

然后启动该应用
```
kubectl create -f kubernetes-dashboard.yaml
```

接下来可以在浏览中查看 
http://172.18.26.2:8080/ui  

# 6、Scaling
```
kubectl scale --replicas=3 deployment/kubernetes-dashboard --namespace="kube-system"
```
这将在3个节点上部署dashboard

http://172.18.26.2:8080/ui  
http://172.18.26.3:8080/ui  
http://172.18.26.4:8080/ui  

# 7. Hello world
```
gcr.io/google_containers/echoserver:1.4
```

![](images/Deploy-a-Containerized-App.png)

![](images/Workloads1.png)

![](images/Workloads2.png)