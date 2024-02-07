在Kubernetes上使用NFS volume
===========================

An **nfs** volume allows an existing **nfs** (Network File System) share to be mounted into your pod. Unlike emptyDir, which is erased when a Pod is removed, the contents of an **nfs** volume are preserved and the volume is merely unmounted. This means that an **nfs** volume can be pre-populated with data, and that data can be “handed off” between pods. **nfs** can be mounted by multiple writers simultaneously.

> Important: You must have your own **nfs** server running with the share exported before you can use it

# 1. Setup NFS

## 1.1  Install Server 

### ubuntu
```
apt-get install nfs-kernel-server
```
### centos
```
yum -y install nfs-utils rpcbind
service rpcbind start
chkconfig rpcbind on
service nfs start
chkconfig nfs on
```

## 1.2 Config Server
```
mkdir /ShareData
chmod 777 -R /ShareData
```
```
vi /etc/exports
/ShareData *(rw,async,no_root_squash,no_subtree_check)
```
```
exportfs -ra
/ShareData         	172.18.0.0/16
```
## 1.3 Install Client
### centos
```
yum -y install nfs-utils
```
### ubuntu
```
apt-get install -y nfs-common 
```

## 1.4 Config Client
```
mkdir /nfsdemo
mount -t nfs 172.18.26.1:/ShareData /nfsdemo # 假定172.18.26.3 是NFS服务器IP
```

## 1.5 Manage with Webmin

[See this page for instructions on how to install.](http://172.18.3.103/Hakugei/Home/wikis/webmin)

# 2. NFS based persistent volume
Create the the persistent volume and the persistent volume claim for your NFS server. The persistent volume and claim gives us an indirection that allow multiple pods to refer to the NFS server using a symbolic name rather than the hardcoded server address.

## 2.1 nfs-pv.yaml
```
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs
spec:
  capacity:
    storage: 1Mi
  accessModes:
    - ReadWriteMany
  nfs:
    # FIXME: use the right IP
    server: 172.18.26.25
    path: "/root"
```
```
> kubectl create -f nfs-pv.yaml
```

## 2.2 nfs-pvc.yaml
```
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: nfs
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Mi
```
```
> kubectl create -f nfs-pvc.yaml
```

# 3. Create Web server using nfs
The web server controller is an another simple replication controller demonstrates reading from the NFS share exported above as a NFS volume and runs a simple web server on it.

## 3.1 nfs-web-rc.yaml
```
apiVersion: v1
kind: ReplicationController
metadata:
  name: nfs-web
spec:
  replicas: 3
  selector:
    role: web-frontend
  template:
    metadata:
      labels:
        role: web-frontend
    spec:
      containers:
      - name: web
        image: gcr.io/google_containers/echoserver:1.4
        ports:
          - name: web
            containerPort: 8080
        volumeMounts:
            # name must match the volume name below
            - name: nfs
              mountPath: "/nfs25"
      volumes:
      - name: nfs
        persistentVolumeClaim:
          claimName: nfs
```
```
> kubectl create -f nfs-web-rc.yaml
```

## 3.2 nfs-web-service.yaml
```
kind: Service
apiVersion: v1
metadata:
  name: nfs-web
spec:
  type: NodePort
  ports:
    - port: 8080
      nodeport: 30080
  selector:
    role: web-frontend
```
```
> kubectl create -f nfs-web-service.yaml
```

## 3.3 验证
```
> kubectl get pod
NAME               READY     STATUS    RESTARTS   AGE
nfs-web-1skg0      1/1       Running   0          54m
nfs-web-lz4cz      1/1       Running   0          2m
nfs-web-l8jko      1/1       Running   0          2m
```
```
> kubectl exec nfs-web-lz4cz -- ls /nfs25
1.txt <====预先准备在172.18.26.25上的

> kubectl exec nfs-web-lz4cz -- ls /
README.md
bin
boot
dev
etc
home
lib
lib64
media
mnt
nfs25
opt
proc
root
run
sbin
srv
sys
tmp
usr
var

```