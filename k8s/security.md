轻松了解Kubernetes认证功能
========================

> By Qinghua Gao  发表于 2016-04-29 http://qinghua.github.io/kubernetes-security/

文章目录
1. 准备工作
2. 部署
3. 验证
4. 简化kubectl

[Kubernetes](whatisk8s)简称k8s，是谷歌于2014年开始主导的开源项目，提供了以容器为中心的部署、伸缩和运维平台。截止目前它的最新版本为1.2。搭建环境之前建议先了解一下kubernetes的相关知识，可以参考《如果有10000台机器，你想怎么玩？》系列文章。本文介绍kubernetes的安全性配置。

# 准备工作

首先需要搭建kubernetes集群环境，可以参考《轻松搭建Kubernetes 1.2版运行环境》来安装自己的kubernetes集群，运行到flannel配置完成即可。接下来的api server等设置的参数可以参考本文。

结果应该是有三台虚拟机，一台叫做master，它的IP是192.168.33.17，运行着k8s的api server、controller manager和scheduler；另两台叫做node1和node2，它们的IP分别是192.168.33.18和192.168.33.19，运行着k8s的kubelet和kube-proxy，当做k8s的两个节点。

# 部署

最简单的方式就是通过基于CSV的基本认证。首先需要创建api server的基本认证文件：
```
#master

mkdir security

echo 123456,admin,qinghua > security/basic_auth.csv                      # 格式：密码,用户名,用户ID
```
然后就可以生成CA和api server的证书了：
```
#master

cd security

openssl genrsa -out ca.key 2048
openssl req -x509 -new -nodes -key ca.key -subj "/CN=192.168.33.17" -days 10000 -out ca.crt
openssl genrsa -out server.key 2048
openssl req -new -key server.key -subj "/CN=192.168.33.17" -out server.csr
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 10000

cd ..
```
上面的命令会生成若干证书相关文件，作用如下：

* ca.key：自己生成的CA的私钥，用于模拟一个CA
* ca.crt：用自己的私钥自签名的CA证书
* server.key：api server的私钥，用于配置api server的https
* server.csr：api server的证书请求文件，用于请求api server的证书
* server.crt：用自己模拟的CA签发的api server的证书，用于配置api server的https

接下来启动api server，参数的作用可以参考kube-apiserver官方文档：
```
#master

docker run -d \
  --name=apiserver \
  --net=host \
  -v /home/vagrant/security:/security \
  gcr.io/google_containers/kube-apiserver:e68c6af15d4672feef7022e94ee4d9af \
  kube-apiserver \
  --advertise-address=192.168.33.17 \
  --admission-control=ServiceAccount \
  --insecure-bind-address=0.0.0.0 \
  --etcd-servers=http://192.168.33.17:4001 \
  --service-cluster-ip-range=11.0.0.0/16 \
  --tls-cert-file=/security/server.crt \
  --tls-private-key-file=/security/server.key \
  --secure-port=443 \
  --basic-auth-file=/security/basic_auth.csv
```
还需要启动controller manager，参数的作用可以参考kube-controller-manager官方文档：
```
#master

docker run -d \
  --name=cm \
  -v /home/vagrant/security:/security \
  gcr.io/google_containers/kube-controller-manager:b9107c794e0564bf11719dc554213f7b \
  kube-controller-manager \
  --master=192.168.33.17:8080 \
  --cluster-cidr=10.245.0.0/16 \
  --allocate-node-cidrs=true \
  --root-ca-file=/security/ca.crt \
  --service-account-private-key-file=/security/server.key
```
最后是scheduler，参数的作用可以参考kube-scheduler官方文档：
```
#master

docker run -d \
  --name=scheduler \
  gcr.io/google_containers/kube-scheduler:903b34d5ed7367ec4dddf846675613c9 \
  kube-scheduler \
  --master=192.168.33.17:8080
```
可以运行以下命令来确认安全配置已经生效：
```
#master

curl -k -u admin:123456 https://127.0.0.1/
curl -k -u admin:123456 https://127.0.0.1/api/v1
```
最后启动kubelet和kube-proxy，参数的作用可以参考kubelet官方文档和kube-proxy官方文档：
```
#node1 node2

NODE_IP=`ifconfig eth1 | grep 'inet addr:' | cut -d: -f2 | cut -d' ' -f1`

sudo kubernetes/server/bin/kubelet \
  --api-servers=192.168.33.17:8080 \
  --cluster-dns=11.0.0.10 \
  --cluster-domain=cluster.local \
  --hostname-override=$NODE_IP \
  --node-ip=$NODE_IP > kubelet.log 2>&1 &

sudo kubernetes/server/bin/kube-proxy \
  --master=192.168.33.17:8080 \
  --hostname-override=$NODE_IP > proxy.log 2>&1 &
```

# 验证

如果需要通过https访问，kubectl的命令就略微有点儿麻烦了，需要用basic_auth.csv里配置的admin/123456来登录：
```
#master

kubernetes/server/bin/kubectl -s https://192.168.33.17 --insecure-skip-tls-verify=true --username=admin --password=123456 get po
```
因为8080端口还开着，所以也可以通过http访问：
```
#master

kubernetes/server/bin/kubectl -s http://192.168.33.17:8080 get po
```
配置完成后，可以看到系统里有TYPE为kubernetes.io/service-account-token的秘密：
```
#master

kubernetes/server/bin/kubectl -s http://192.168.33.17:8080 get secret
```
里面有三条数据，分别是ca.crt，namespace和token，可以通过以下命令看到：
```
master

kubernetes/server/bin/kubectl -s http://192.168.33.17:8080 describe secret
```
如果你通过kubernetes启动了一个pod，就可以在容器的/var/run/secrets/kubernetes.io/serviceaccount/目录里看到以三个文件的形式看到这三条数据（这是--admission-control=ServiceAccount的功劳），当pod需要访问系统服务的时候，就可以使用它们了。可以使用以下命令看到系统的服务账号：
```
master

kubernetes/server/bin/kubectl -s http://192.168.33.17:8080 get serviceAccount
```

# 简化kubectl

如果我们通过设置`--insecure-port=0`把api server的http端口关闭，那它就只能通过https访问了：
```
#master

docker rm -f apiserver
docker run -d \
  --name=apiserver \
  --net=host \
  -v /home/vagrant/security:/security \
  gcr.io/google_containers/kube-apiserver:e68c6af15d4672feef7022e94ee4d9af \
  kube-apiserver \
  --advertise-address=192.168.33.17 \
  --admission-control=ServiceAccount \
  --insecure-bind-address=0.0.0.0 \
  --etcd-servers=http://192.168.33.17:4001 \
  --service-cluster-ip-range=11.0.0.0/16 \
  --tls-cert-file=/security/server.crt \
  --tls-private-key-file=/security/server.key \
  --secure-port=443 \
  --basic-auth-file=/security/basic_auth.csv \
  --insecure-port=0
```
这样的话，就连取个pod都得这么麻烦：
```
#master

kubernetes/server/bin/kubectl -s https://192.168.33.17 --insecure-skip-tls-verify=true --username=admin --password=123456 get po
```
幸运的是，kubernetes提供了一种方式，让我们可以大大简化命令，只用这样就好了：
```
#master

kubernetes/server/bin/kubectl get po
```
下面就让我们来试一下吧！首先用`kubectl config`命令来配置admin用户：
```
#master

kubernetes/server/bin/kubectl config set-credentials admin --username=admin --password=123456
```
然后是api server的访问方式，给集群起个名字叫qinghua：
```
#master

kubernetes/server/bin/kubectl config set-cluster qinghua --insecure-skip-tls-verify=true --server=https://192.168.33.17
```
接下来创建一个context，它连接用户admin和集群qinghua：
```
#master

kubernetes/server/bin/kubectl config set-context default/qinghua --user=admin --namespace=default --cluster=qinghua
```
最后设置一下默认的context：
```
#master

kubernetes/server/bin/kubectl config use-context default/qinghua
```
然后就可以用我们的简化版啦：
```
#master

kubernetes/server/bin/kubectl get po
```
可以通过以下命令来看到当前kubectl的配置：
```
#master

kubernetes/server/bin/kubectl config view
```
能够看到如下内容：
```
apiVersion: v1
clusters:
- cluster:
    insecure-skip-tls-verify: true
    server: https://192.168.33.17
  name: qinghua
contexts:
- context:
    cluster: qinghua
    namespace: default
    user: admin
  name: default/qinghua
current-context: default/qinghua
kind: Config
preferences: {}
users:
- name: admin
  user:
    password: "123456"
    username: admin
```
实际上这些配置都存放在`~/.kube/config`文件里：
```
master

cat ~/.kube/config
```
修改这个文件也可以实时生效。细心的童鞋们可以看到，cluster、context和users都是集合，也就是说如果需要切换用户和集群等，只需要设置默认context就可以了，非常方便。