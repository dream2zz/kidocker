采用Kubespray单机部署Kubernetes
===

Deploy a Production Ready Kubernetes Cluster

* Can be deployed on AWS, GCE, Azure, OpenStack or Baremetal
* High available cluster
* Composable (Choice of the network plugin for instance)
* Support most popular Linux distributions
* Continuous integration tests

# 1. 准备

选择CentOS7.4操作系统，安装时不要分配swap分区

文档中脚本默认均以root用户执行

安装 epel 源并更新
```
yum install epel-release -y
```

安装依赖工具
```
yum install wget git python python-pip -y
```

安装Python3
```
yum -y groupinstall "Development tools"
yum -y install zlib-devel bzip2-devel openssl-devel ncurses-devel sqlite-devel readline-devel tk-devel gdbm-devel db4-devel libpcap-devel xz-devel
wget https://www.python.org/ftp/python/3.6.2/Python-3.6.4.tar.xz
mkdir /usr/local/python3
tar -xvJf  Python-3.6.4.tar.xz
cd Python-3.6.4
./configure --prefix=/usr/local/python3
make && make install
ln -s /usr/local/python3/bin/python3 /usr/bin/python3
ln -s /usr/local/python3/bin/pip3 /usr/bin/pip3
# 在命令行中输入python3测试
```

安装ansible
```
pip install pip --upgrade -i http://mirrors.aliyun.com/pypi/simple/ --trusted-host mirrors.aliyun.com
pip install --no-cache-dir ansible -i http://mirrors.aliyun.com/pypi/simple/ --trusted-host mirrors.aliyun.com
pip install --no-cache-dir netaddr -i http://mirrors.aliyun.com/pypi/simple/ --trusted-host mirrors.aliyun.com
```
配置ansible ssh密钥登陆($IP为本虚机地址，按照提示输入 yes 和 root 密码)
```
ssh-keygen -t rsa -b 2048
ssh-copy-id $IP #
```

# 3. 替换官方镜像源

roles/download/defaults/main.yml
```yaml
kube_version: v1.9.2

# Containers
etcd_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/etcd"
etcd_image_tag: "{{ etcd_version }}"
flannel_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/flannel"
flannel_image_tag: "{{ flannel_version }}"
flannel_cni_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/flannel-cni"
flannel_cni_image_tag: "{{ flannel_cni_version }}"
calicoctl_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/calico_ctl"
calicoctl_image_tag: "{{ calico_ctl_version }}"
calico_node_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/calico_node"
calico_node_image_tag: "{{ calico_version }}"
calico_cni_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/calico_cni"
calico_cni_image_tag: "{{ calico_cni_version }}"
calico_policy_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/kube-controllers"
calico_policy_image_tag: "{{ calico_policy_version }}"
calico_rr_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/routereflector"
calico_rr_image_tag: "{{ calico_rr_version }}"
hyperkube_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/hyperkube"
hyperkube_image_tag: "{{ kube_version }}_coreos.0"
pod_infra_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/pause-amd64"
pod_infra_image_tag: "{{ pod_infra_version }}"
install_socat_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/install-socat"
install_socat_image_tag: "latest"
netcheck_version: "v1.0"
netcheck_agent_img_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/k8s-netchecker-agent"
netcheck_agent_tag: "{{ netcheck_version }}"
netcheck_server_img_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/k8s-netchecker-server"
netcheck_server_tag: "{{ netcheck_version }}"
weave_kube_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/weave-kube"
weave_kube_image_tag: "{{ weave_version }}"
weave_npc_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/weave-npc"
weave_npc_image_tag: "{{ weave_version }}"
contiv_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/netplugin"
contiv_image_tag: "{{ contiv_version }}"
contiv_auth_proxy_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/auth_proxy"
contiv_auth_proxy_image_tag: "{{ contiv_version }}"
cilium_image_repo: "docker.io/cilium/cilium"
cilium_image_tag: "{{ cilium_version }}"


nginx_image_repo: nginx
nginx_image_tag: 1.13
dnsmasq_version: 2.78
dnsmasq_image_repo: "andyshinn/dnsmasq"
dnsmasq_image_tag: "{{ dnsmasq_version }}"
kubedns_version: 1.14.8
kubedns_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/k8s-dns-kube-dns-amd64"
kubedns_image_tag: "{{ kubedns_version }}"
dnsmasq_nanny_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/k8s-dns-dnsmasq-nanny-amd64"
dnsmasq_nanny_image_tag: "{{ kubedns_version }}"
dnsmasq_sidecar_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/k8s-dns-sidecar-amd64"
dnsmasq_sidecar_image_tag: "{{ kubedns_version }}"
dnsmasqautoscaler_version: 1.1.2
dnsmasqautoscaler_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/cluster-proportional-autoscaler-amd64"
dnsmasqautoscaler_image_tag: "{{ dnsmasqautoscaler_version }}"
kubednsautoscaler_version: 1.1.2
kubednsautoscaler_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/cluster-proportional-autoscaler-amd64"
kubednsautoscaler_image_tag: "{{ kubednsautoscaler_version }}"
test_image_repo: busybox
test_image_tag: latest
elasticsearch_version: "v2.4.1"
elasticsearch_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/elasticsearch"
elasticsearch_image_tag: "{{ elasticsearch_version }}"
fluentd_version: "1.22"
fluentd_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/fluentd-elasticsearch"
fluentd_image_tag: "{{ fluentd_version }}"
kibana_version: "v4.6.1"
kibana_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/kibana"
kibana_image_tag: "{{ kibana_version }}"

helm_version: "v2.8.1"
helm_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/k8s-helm"
helm_image_tag: "{{ helm_version }}"
tiller_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/tiller"
tiller_image_tag: "{{ helm_version }}"
vault_image_repo: "vault"
vault_image_tag: "{{ vault_version }}"
```

roles/kubernetes-apps/ansible/defaults/main.yml
```yaml
# Images
kubedns_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/k8s-dns-kube-dns-amd64"
kubedns_image_tag: "{{ kubedns_version }}"
dnsmasq_nanny_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/k8s-dns-dnsmasq-nanny-amd64"
dnsmasq_nanny_image_tag: "{{ kubedns_version }}"
dnsmasq_sidecar_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/k8s-dns-sidecar-amd64"
dnsmasq_sidecar_image_tag: "{{ kubedns_version }}"
kubednsautoscaler_image_repo: "registry.cn-hangzhou.aliyuncs.com/kubespray24/cluster-proportional-autoscaler-amd64"
kubednsautoscaler_image_tag: "{{ kubednsautoscaler_version }}"

# Dashboard
dashboard_enabled: true
dashboard_image_repo: registry.cn-hangzhou.aliyuncs.com/kubespray24/kubernetes-dashboard-amd64
dashboard_image_tag: v1.8.1
```

# 4. 安装K8S
```
# Copy ``inventory/sample`` as ``inventory/mycluster``
cp -rfp inventory/sample inventory/mycluster

# Update Ansible inventory file with inventory builder
declare -a IPS=($IP)
CONFIG_FILE=inventory/mycluster/hosts.ini python3 contrib/inventory_builder/inventory.py ${IPS[@]}

# Review and change parameters under ``inventory/mycluster/group_vars``
cat inventory/mycluster/group_vars/all.yml
cat inventory/mycluster/group_vars/k8s-cluster.yml

# Deploy Kubespray with Ansible Playbook
ansible-playbook -i inventory/mycluster/hosts.ini cluster.yml
```

# 5. 访问DashBoard UI

在浏览器里打开 https://172.18.24.201:6443/ui，会跳转到如下界面：

![](images/20180320110342.png)

创建`admin-role.yaml`，填写以下内容：

```yaml
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: admin
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: ServiceAccount
  name: admin
  namespace: kube-system
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin
  namespace: kube-system
  labels:
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
```

```
[root@node1 ~]# kubectl create -f admin-role.yaml
clusterrolebinding "admin" created
serviceaccount "admin" created
[root@node1 ~]# kubectl -n kube-system get secret|grep admin
admin-token-cq98f                                kubernetes.io/service-account-token   3         12s
[root@node1 ~]# kubectl -n kube-system describe secret admin-token-x9p5k
Error from server (NotFound): secrets "admin-token-x9p5k" not found
[root@node1 ~]# kubectl -n kube-system describe secret admin-token-cq98f
Name:         admin-token-cq98f
Namespace:    kube-system
Labels:       <none>
Annotations:  kubernetes.io/service-account.name=admin
              kubernetes.io/service-account.uid=140ecbc5-2b4e-11e8-b8b9-00505683524f

Type:  kubernetes.io/service-account-token

Data
====
namespace:  11 bytes
token:      eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJrdWJlLXN5c3RlbSIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VjcmV0Lm5hbWUiOiJhZG1pbi10b2tlbi1jcTk4ZiIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VydmljZS1hY2NvdW50Lm5hbWUiOiJhZG1pbiIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VydmljZS1hY2NvdW50LnVpZCI6IjE0MGVjYmM1LTJiNGUtMTFlOC1iOGI5LTAwNTA1NjgzNTI0ZiIsInN1YiI6InN5c3RlbTpzZXJ2aWNlYWNjb3VudDprdWJlLXN5c3RlbTphZG1pbiJ9.BV2bHNMNuLmglJ08ADkQKbDr4mWMo71dL4vaZvViIYqnnWVkRN-WQ9BUxQpFvfZQsRC6gJ9c95hyWpNDLBmhAel_v1tNzWTA88Wo2qy6oUY-fAdEZOPRJKMM9hIomLFnYR4QVJlh7EoH6LINr68-RRWNQtLZCA_sxFfePJ2FhVZvrUBA2sDwtObeHSpgcLJteuofXh3KnDfKtWucBj-9FTZbrYVhOPPgRkmrI1jIr4HbS5-uJ_rGVeQPnlkvn4iDR5e_MnLfnhhoo1kMPrOinkWVdPtFtFrQ_FGQr59iiTQOeCgg5SERR4wNAxIpIkbIKoA34Rja7fHH2mHy9XdiqQ
ca.crt:     1090 bytes
```

在登陆界面输入token，进入管理界面

![](images/20180320110956.png)