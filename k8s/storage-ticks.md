Kubernetes【存储】琐碎信息
==================

Pv:是集群中的某个网络存储中对应的一块存储，它是一种独立于计算资源而存在的一种实体资源，通常我们定义一个网络存储，然后从中划出一个网盘并挂载在虚拟机上
* pv属于网络存储，不属于任何node，但可以在每个node上访问
* Pv不是定义在pod上，而是独立于pod之外的
pvc：某个pod想申请某种条件的pv，需要定义它
 
# volume和claim的生命周期
 
## 可以提供的

静态的，一个集群的管理者会生成很多pv，他们掌控一些存储的细节并将这些存储给集群用户用，这些pv存在于k8s的api，可以用于消耗

动态的，当没有静态的pv可以用时，管理者需要创建适合用户的pvc，然后集群会动态的提供一个volume给pvc，这个提供是基于storageclass：这个pvc必须请求一个calss而且管理者必须创建和配置这个class以供使用，如果没有声明的话，将不会有动态资源提供
 
## 正在绑定的

假如一个pvc设置了一定的storage和access modes，并且有对应的pv，那么就会动态提供资源。一个在master上面的control loop 一直寻在监控pvc，然后找到一个pv进行匹配。

假如需要匹配的volume不存在，那么pvc一直保持unbound状态，pvc一般会与可利用的匹配的volume绑定。假如集群提供了一个50g的pv，那么请求100g的pvc将不匹配，除非集群添加了一个100g的pv
 
## 正在使用的

pod使用claim作为volume,集群通过检查claim来找到绑定的volume，然后提供volume给pod。volumes提供多种multiple access modes，用户当需要为pod使用volume 时候，需要声明期望的mode一旦用户有claim，而且claim被绑定，那么被绑定的pv就属于用户。用户们通过包含在pod的volume模块中的pvc，调度pods和使用声明的pv
 
## 正在释放的

当一个用户已经用完它们的volume，可以通过api删除pvc，用以资源的回收。当pvc已被删除时，这时关联的volume是released状态，但是还不能被另外的pvc使用。因为之前pvc产生的数据仍然在volume中，必须根据规则进行处理。
 
## 重新声明的
当volume从它的pvc释放出来之后，pv的recaim规则会告诉集群该对volume做什么。目前来说，volume既可以被保留，也可以被回收利用或者被删除。deletion会删除k8s的pv，同样会删除关联的存储（aws，gce，azure， cinder volume）。动态提供的volume通常会被删除
 
---
```
pv
apiVersion: v1
  kind: PersistentVolume
  metadata:
    name: pv0003
    annotations:
      volume.beta.kubernetes.io/storage-class: "slow"
  spec:
    capacity:
      storage: 5Gi
    accessModes:
      - ReadWriteOnce
    persistentVolumeReclaimPolicy: Recycle
    nfs:
      path: /tmp
      server: 172.17.0.2
```

capacity：存储属性

access modes：不同的虚拟资源会有不同的存储能力和不同的access mode

The access modes are:

* ReadWriteOnce – the volume can be mounted as read-write by a single node
* ReadOnlyMany – the volume can be mounted read-only by many nodes
* ReadWriteMany – the volume can be mounted as read-write by many nodes

In the CLI, the access modes are abbreviated to:

* RWO - ReadWriteOnce
* ROX - ReadOnlyMany
* RWX - ReadWriteMan

class：pv的annotation 的class volume.beta.kubernetes.io/storage-class会和StorageClass的name关联起来。pv的class会和pvc的class关联起来
 
reclaim policy：
* Retain – manual reclamation
* Recycle – basic scrub (“rm -rf /thevolume/*”)
* Delete – associated storage asset such as AWS EBS, GCE PD, Azure Disk, or OpenStack Cinder volume is deleted

Currently, only NFS and HostPath support recycling. AWS EBS, GCE PD, Azure Disk, and Cinder volumes support deletion.

volume所处的几个阶段：
* Available – a free resource that is not yet bound to a claim
* Bound – the volume is bound to a claim
* Released – the claim has been deleted, but the resource is not yet reclaimed by the cluster
* Failed – the volume has failed its automatic reclamation

pvc：通常包括 spec和status
```
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: myclaim
  annotations:
    volume.beta.kubernetes.io/storage-class: "slow"
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 8Gi
  selector:
    matchLabels:
      release: "stable"
    matchExpressions:
      - {key: environment, operator: In, values: [dev]}
```

**access modes**

resources：请求的资源大小
seletor ：pvc通常包含一个label selector 来挑选合适的volume。当volume的label和label seletor对应起来，才可以用这些volume。
 
**volume的claim**

pod通过claim才可以用volume存储。claim必须和pod存在于同一个namespace。这个集群从pod的namespace找到claim，然后和pv关联起来。然后volume可以挂载在pod上
```
kind: Pod
apiVersion: v1
metadata:
  name: mypod
spec:
  containers:
    - name: myfrontend
      image: dockerfile/nginx
      volumeMounts:
      - mountPath: "/var/www/html"
        name: mypd
  volumes:
    - name: mypd
      persistentVolumeClaim:
        claimName: myclaim
```