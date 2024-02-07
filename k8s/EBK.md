## 3.7 基于Kubernetes环境的监控预研  

### 3.7.1 EBK部署参考  
本次部署仅作为参考学习用，网络拓扑图如下图所示，相关部署参考配置将在后面做详细解释。  

![1531103283362](images/1531103283362.png)  

> **Note：** 本次部署环境为： Ubuntu 16.04.4 LTS + Kubernetes1.10.1 + Docker17.03.2-ce，以下部署相关的Yaml文件都是基于上述环境并按上图进行示例编写的，上图不作为最终实施部署方案，仅用作学习参考用。  

#### 3.7.1.1 ElasticSearch    

* `es-dep.yaml`

```yaml
# 指定部署类型为Deployment，实际生产时可能会部署为有状态的StatefulSet类型，并使用持久存储。
apiVersion: apps/v1beta1
kind: Deployment
# 设置元数据信息
metadata:
  name: es
  #namespace: ebk
  labels:	# （可选）为该Pod添加标签
    component: elasticsearch	# 标签的key可任意命名
# 具体部署配置项
spec:
  selector:		# （可选）指定具体的template，如指定则必须与spec.template.metadata.labels匹配，否则会创建不成功；如不指定，则默认是spec.template.metadata.labels
    matchLabels:
      component: elasticsearch
  replicas: 3	# 副本数量为3，可理解为部署3个Pod
  template:		# 每个副本的模板配置项，k8s会按下面配置创建各个副本
    metadata:
      labels:
        component: elasticsearch
    spec:
      # 创建一个初始容器，此容器会先于后面的应用容器运行，只有init容器运行成功后，才会运行后面的应用容器，如果运行失败，默认kubernetes会不断重启该Pod，直到Init容器成功运行。
      # 下面这种写法仅支持kubernetes1.6以上版本，在此用于为该Pod设置特殊资源请求或限制的最大值
      initContainers:
      - name: init-sysctl	# 容器名，任意指定
        image: busybox:1.27.2	# 指定镜像来源及版本号
        command:	# 容器启动命令，这里要设置vm.max_map_count=262144，否则ES会无法启动。
        - sysctl
        - -w
        - vm.max_map_count=262144
        securityContext:	# 开启特权，否则上面命令无法执行
          privileged: true
      # 配置具体的应用容器
      containers:
      - name: es-node
        # 下面镜像来源k8s官方示例推荐，其在官方elasticsearch镜像基础上，对一些配置进行了抽取，此更便于我们的部署配置
        image: quay.io/pires/docker-elasticsearch-kubernetes:6.3.0
        # 配置应用容器中的环境变量
        env:
        - name: NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: CLUSTER_NAME	# 环境变量名
          value: myesdb		    # 变量值
          # 指定DISCOVERY_SERVICE变量值，镜像中默认值为elasticsearch-discovery，这里修改为下面配置的Service的名称elasticsearch
        - name: DISCOVERY_SERVICE
          value: "elasticsearch"
          # 设置集群的最小主节点数量，这里表示集群至少需要2个主节点才能运行
        - name: NUMBER_OF_MASTERS
          value: "2"
          # 实际生产部署可能需要对Master/Ingest/Data功能做拆分，不会集中在一个Pod上。
          # 设置该容器是否是主节点
        - name: NODE_MASTER
          value: "true"
          # 设置该容器是否用于摄取期间的Document预处理
        - name: NODE_INGEST
          value: "true"
          # 设置是否用于数据存储
        - name: NODE_DATA
          value: "true"
          # 设置开启HTTP API
        - name: HTTP_ENABLE
          value: "true"
          # 设置网络参数，否则会启动报错
        - name: NETWORK_HOST
          value: _site_,_lo_
          # 设置JVM参数
        - name: ES_JAVA_OPTS
          value: -Xms512m -Xmx512m
          # 设置CPU资源
        - name: PROCESSORS
          valueFrom:
            resourceFieldRef:
              resource: limits.cpu
        # 设置最低资源及最大资源限制
        resources:
          requests:
            cpu: 0.25
          limits:
            cpu: 1
        # 设置容器暴露的端口
        ports:
        - containerPort: 9200
          name: http
        - containerPort: 9300
          name: transport
        # 设置卷挂载
        volumeMounts:
        - name: storage
          mountPath: /data
      # 实际部署时此处应定义主机上真是存在的路径，用于ES做卷挂载进行数据存储，这里使用emptyDir，在ES Pod重启后，之前的数据会丢失。
      volumes:
      - name: storage
        emptyDir: {}
      # 实际生产部署需要指定数据具体存储路径，下面为使用主机/ebk/es/data来挂载存储ES数据
      #- name: storage
        #hostPath:
          #path: /ebk/es/data
```

* `es-svc.yaml`

```yaml
# 指定部署类型为Service
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch
  labels:
    component: elasticsearch
spec:
  selector:
    component: elasticsearch
  # 设置Service暴露的端口为9200和9300，如不配置targetPort（Pod暴露的端口），则默认和配置的port相同
  ports:
  - name: http
    port: 9200
    #targetPort： 9200
    protocol: TCP
  - name: transport
    port: 9300
    protocol: TCP
```

> **遇到的问题：**  
>
> - 因未修改vm.max_map_count的值导致ES容器无法启动；
> - 在k8s1.5版本使用annotation的方式设置vm.max_map_count=262144无效，导致启动ES容器报错；
> - 由于未将ES服务发现做单独拆分，所以需要修改配置DISCOVERY_SERVICE的值，否则无法访问该集群；
> - 需要配置NETWORK_HOST，否则ES API会无法访问，或者启动会报错。

```shell
# 按顺序创建Pod和Service
kubectl create -f es-dep.yaml
kubectl create -f es-svc.yaml

# 创建完成后可以使用下面命令查看Pod和Service状态
root@hakugei-1:~# kubectl get pod
NAME                                    READY     STATUS    RESTARTS   AGE
es-b74f6c98b-bbmj2                      1/1       Running   0          4d
es-b74f6c98b-dn74h                      1/1       Running   0          4d
es-b74f6c98b-fbkf5                      1/1       Running   0          4d
root@hakugei-1:~# kubectl get svc
NAME               TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)             AGE
elasticsearch      ClusterIP   10.43.175.154   <none>        9200/TCP,9300/TCP   4d
```

```shell
# 使用命令查看es service的IP地址，然后通过命令查看集群部署是否成功
root@hakugei-1:~# kubectl get svc elasticsearch
NAME            TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)             AGE
elasticsearch   ClusterIP   10.43.175.154   <none>        9200/TCP,9300/TCP   4d
root@hakugei-1:~# curl 10.43.175.154:9200
{
  "name" : "es-b74f6c98b-dn74h",
  "cluster_name" : "myesdb",
  "cluster_uuid" : "5C0TiQmqR2yYVTl_QDjeRA",
  "version" : {
    "number" : "6.3.0",
    "build_flavor" : "default",
    "build_type" : "tar",
    "build_hash" : "424e937",
    "build_date" : "2018-06-11T23:38:03.357887Z",
    "build_snapshot" : false,
    "lucene_version" : "7.3.1",
    "minimum_wire_compatibility_version" : "5.6.0",
    "minimum_index_compatibility_version" : "5.0.0"
  },
  "tagline" : "You Know, for Search"
}
root@hakugei-1:~# curl 10.43.175.154:9200/_cluster/health?pretty
{
  "cluster_name" : "myesdb",
  "status" : "green",
  "timed_out" : false,
  "number_of_nodes" : 3,
  "number_of_data_nodes" : 3,
  "active_primary_shards" : 41,
  "active_shards" : 82,
  "relocating_shards" : 0,
  "initializing_shards" : 0,
  "unassigned_shards" : 0,
  "delayed_unassigned_shards" : 0,
  "number_of_pending_tasks" : 0,
  "number_of_in_flight_fetch" : 0,
  "task_max_waiting_in_queue_millis" : 0,
  "active_shards_percent_as_number" : 100.0
}
```

#### 3.7.1.2 Kibana

* `kibana-dep.yaml`

```yaml
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: kibana
  labels:
    component: kibana
spec:
  replicas: 1
  selector:
    matchLabels:
      component: kibana
  template:
    metadata:
      labels:
        component: kibana
    spec:
      containers:
      - name: kibana
        image: docker.elastic.co/kibana/kibana-oss:6.3.0	# 使用-oss镜像，此镜像不包含x-pack插件
        # 配置ES集群名称
        env:
        - name: CLUSTER_NAME
          value: myesdb
        resources:
          limits:
            cpu: 1000m
          requests:
            cpu: 100m
        ports:
        - containerPort: 5601
          name: http
```

* `kibana-svc.yaml`

```shell
apiVersion: v1
kind: Service
metadata:
  name: kibana
  labels:
    component: kibana
spec:
  selector:
    component: kibana
  # 使用NodePort类型，暴露一个端口供集群外部环境访问
  type: NodePort
  ports:
    - name: http
      port: 5601
      nodePort: 30056
```

> **遇到的问题：**
>
> * nodePort默认只能设置为30000~32767之间的值，否则会报错导致无法访问，该范围可通过apiserver的参数修改。  

```shell
# 创建pod和service
kubectl create -f kibana-dep.yaml
kubectl create -f kibana-svc.yaml

# 创建成功后，浏览器访问下面地址可进入kibana主页，注意这里的IP可以是K8S环境中任一node的IP地址
http://172.18.24.201:30056
```

#### 3.7.1.3 Filebeat

##### 3.7.1.3.1 与App容器分开部署  

- 应用镜像制作Dockerfile  

```dockerfile
# 这里使用alpine版本的JDK，其仅包含最基本的linux核心组件，这样可以让镜像大小达到最小
FROM openjdk:8-jdk-alpine
# 设置容器时区的方式之一
#RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    #echo 'Asia/Shanghai' > /etc/timezone
# 将与Dockerfile同级"目录"下的应用jar文件复制镜像的根路径'/'下，并重命名为app.jar
ADD xseed-system1-backend-2.0.0.jar /app.jar
# 暴露端口8666
EXPOSE 8666
# 运行容器时执行相应命令前台启动springboot应用
ENTRYPOINT ["java","-Djava.security.egd=file:/dev/./urandom","-jar","/app.jar"]
```

```shell
# 使用下面命令创建镜像，'-t'指定镜像名称
docker build -t my/spring-boot-filebeat .

# 上传镜像到Harbor仓库，先登录到仓库，然后给镜像打上标签，最后push到仓库
docker login -u admin -p Admin123 172.18.3.108	# 指定仓库地址，然后输入仓库用户的用户名和密码
# 打tag，以仓库ip为前缀，ebk为仓库中已存在（否则push时会失败）的项目名，标签为v1
docker tag my/spring-boot-filebeat 172.18.3.108/ebk/spring-boot-filebeat:v1
# 上传镜像到仓库
docker push 172.18.3.108/ebk/spring-boot-filebeat:v1
```

> **遇到的问题：**  
>
> * 上传镜像是要先登陆；`docker login -u admin -p Admin123 172.18.3.108`
>
> * 打tag时镜像名称中的仓库项目名必须事先创建好，否则无法push。

* `filebeat-cm.yaml`

```yaml
# Filebeat相关配置项，指定ConfigMap类型
apiVersion: v1
kind: ConfigMap
metadata:
  name: filebeat-configmap
data:
  # 下面的配置为参考官方二进制包内的filebeat.yml文件编写的
  # "|-"为yaml语法，意思大致为filebeat.yml的内容按下面的格式原样输出。
  filebeat.yml: |-
    # Filebeat prospectors
    filebeat.prospectors:
    # 配置类型为log，收集/logs路径下，所有以.json结尾的日志文件。
    - type: log
      enabled: true
      paths:
      - /logs/*.json

      ## Multiline options
      # 多行匹配规则设置
      #multiline.pattern: ^\[
      # true表示会对匹配到的行进行合并
      #multiline.negate: true
      # 设置合并到上一行的末尾还是开头
      #multiline.match: after
    
    # Filebeat modules
    filebeat.config.modules:
      path: ${path.config}/modules.d/*.yml
      reload.enabled: false
      #reload.period: 10s

    # General
    #name: filebeat-app-logs
    tags: ["k8s-beat"]

    # Dashboards
    setup.dashboards.enabled: true		# 开启使用官方自带的仪表板

    # Kibana
    setup.kibana:
      host: ${KIBANA_HOST}:${KIBANA_PORT}	# 配置Kibana地址，这里在yaml中使用环境变量的语法方式
  
    # Outputs
    ## Elasticsearch output
    output.elasticsearch:		# 通过环境变量的方式配置es服务地址
      hosts: ['${ELASTICSEARCH_HOST}:${ELASTICSEARCH_PORT}']	# 注意这里的单引号不能少，否则报错
      username: ${ELASTICSEARCH_USERNAME}
      password: ${ELASTICSEARCH_PASSWORD}
```

* `filebeat-dep.yaml`

```yaml
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: spring-boot-filebeat
  labels:
    app-beat: spring-boot-filebeat
spec:
  replicas: 3
  template:
    metadata:
      labels:
        app-beat: spring-boot-filebeat
    spec:
      terminationGracePeriodSeconds: 30	# 设置优雅关闭时间，这里设置30s
      containers:
      - name: spring-boot-filebeat
        # 这里配置使用的是推送到Harbor的应用镜像
        image: 172.18.3.108/ebk/spring-boot-filebeat:v1
        # 注意这里（可选）配置Always，默认情况下如果应用的镜像版本号不变，即使修改了镜像中应用内容并推送到Harbor仓库，其默认情况下会读取本地的镜像，导致应用中修改的内容不生效，配置Always后，每次创建Pod时都会从Harbor仓库下载。
        imagePullPolicy: Always
        ports:
        - containerPort: 8666
        volumeMounts:
        # 配置卷挂载，使应用容器中/logs与下面filebeat的/logs共享，这样filebeat才能读取到应用日志文件
        - name: shared-log
          mountPath: /logs
        # 将主机时区文件与容器中的/etc/localtime进行挂载，这样就让容器与k8s环境的时区保持一致
        - name: timezone
          mountPath: /etc/localtime
        

      - name: filebeat
        image: docker.elastic.co/beats/filebeat:6.3.0
        # 容器启动时的参数，使用/etc/filebeat.yml配置启动
        args: [
          "-c", "/etc/filebeat.yml",
          "-e",
        ]
        securityContext:
          runAsUser: 0	# 容器启动用户
        # 配置ES和Kibana相关环境变量
        env:
        - name: ELASTICSEARCH_HOST
          value: elasticsearch
        - name: ELASTICSEARCH_PORT
          value: "9200"
        - name: ELASTICSEARCH_USERNAME
          value: elastic
        - name: ELASTICSEARCH_PASSWORD
          value: changeme
        - name: KIBANA_HOST
          value: kibana
        - name: KIBANA_PORT
          value: "5601"
        volumeMounts:
        # 共享应用日志"目录"
        - name: shared-log
          mountPath: /logs
        # 共享主机时区设置
        - name: timezone
          mountPath: /etc/localtime
        # 挂载configmap内定义的配置
        - name: config
          mountPath: /etc/filebeat.yml
          readOnly: true
          # 挂载单文件必须写subPath，否则启动报错
          subPath: filebeat.yml
        # 将filebeat的data"目录"与主机上的/ebk/filebeat/data进行挂载
        - name: data
          mountPath: /usr/share/filebeat/data
      volumes:
      # 这里使用emptyDir，重启后原日志文件会丢失，如需保存，那么这里应该配置主机上的一个具体"目录"地址
      - name: shared-log
        emptyDir: {}
      - name: timezone
        hostPath:
          path: /etc/localtime
      - name: data
        hostPath:
          path: /ebk/filebeat/data
      - name: config
        configMap:
          name: filebeat-configmap
```

* `filebeat-svc.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: spring-boot-filebeat
  labels:
    app-beat: spring-boot-filebeat
spec:
  selector:
    app-beat: spring-boot-filebeat
  ports:
    - port: 8666
```

> **遇到的问题：**  
>
> * 单文件的挂载必须配置subPath，否则启动报错；  
> * configmap中的ES地址一定要用引号引起来，否则会报错（一定要注意yaml文件格式对齐等细节）；  
> * filebeat读取不到应用日志文件，这里要配置filebeat和app容器的日志路径共享才行；
> * 要注意时区的配置，默认镜像使用的是UTC时间，非东八区；
> * 注意应用镜像的标签，如果更改了应用，但重新上传镜像时未修改tag，此时需要配置imagePullPolicy为Always，否则重新创建Pod时，应用的修改会不生效。  

```shell
# 按顺序创建资源，尤其要注意ConfigMap一定要先于Pod创建，否则Pod会无法创建成功
kubectl create -f filebeat-cm.yaml
kubectl create -f filebeat-dep.yaml
kubectl create -f filebeat-svc.yaml

# 创建成功后，filebeat会自动采集容器/logs"目录"下的日志文件，读取数据并发送给ES进行存储，我们可以在kibana的Discover页面的filebeat-*索引下看到日志详情
```

##### 3.7.1.3.2 与App合并部署  

* 应用镜像制作Dockerfile  

```dockerfile
#FROM openjdk:8-jdk-alpine	#使用这个作为基镜像，虽然镜像大小会比较小，但filebeat会无法正常运行
#FROM centos:7			   # 使用此作基础镜像，需要配置java环境，且镜像大小也较大，不合适
#FROM openjdk:8-jdk		    # 使用这个作基础镜像，镜像大小比较大，不是最佳方案
FROM openjdk:8-jdk-slim		# 使用此作基础镜像，此为折中方案，镜像大小最小，且filebeat可以正常运行 
# 将统计目录下的filebeat二进制压缩文件解压并复制到/usr/local/下
ADD filebeat-6.3.0-linux-x86_64.tar.gz /usr/local/
# 将容器运行时的脚本文件复制到根目录下
COPY docker-entrypoint /
# 运行一些设置操作
RUN mv /usr/local/filebeat-6.3.0-linux-x86_64 /usr/local/filebeat && \
    cd /usr/local/filebeat && \
    mkdir data logs && \
    chown -R root:root . && \
    chmod 755 /docker-entrypoint
    # 可设置镜像时区，但推荐在yaml配置文件中通过挂载的方式统一各容器时区设置
    #ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    #echo 'Asia/Shanghai' > /etc/timezone
# 将应用jar文件复制为/app.jar
ADD xseed-system1-backend-2.0.0.jar /app.jar
EXPOSE 8666
# 设置容器的工作目录为/
WORKDIR /
# 设置容器运行时执行根目录下docker-entrypoint脚本
ENTRYPOINT ["/docker-entrypoint"]
```

```shell
#! /bin/bash
# 先后台启动filebeat服务
exec nohup /usr/local/filebeat/filebeat -e -c /usr/local/filebeat/filebeat.yml -d "publish" 2>/dev/null &
# 前台启动springboot应用
exec java -Djava.security.egd=file:/dev/./urandom -jar /app.jar 
```

* `filebeat-mix-dep.yaml`

```yaml
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: spring-boot-filebeat-mix
  labels:
    app-beat: spring-boot-filebeat-mix
spec:
  replicas: 3
  template:
    metadata:
      labels:
        app-beat: spring-boot-filebeat-mix
    spec:
      terminationGracePeriodSeconds: 30 #优雅关闭
      containers:
      - name: spring-boot-filebeat
        image: 172.18.3.108/ebk/app-filebeat-mix-slim:v1 
        imagePullPolicy: Always
        env:
        - name: ELASTICSEARCH_HOST
          value: elasticsearch
        - name: ELASTICSEARCH_PORT
          value: "9200"
        - name: ELASTICSEARCH_USERNAME
          value: elastic
        - name: ELASTICSEARCH_PASSWORD
          value: changeme
        - name: KIBANA_HOST
          value: kibana
        - name: KIBANA_PORT
          value: "5601"
        ports:
        - containerPort: 8666
        volumeMounts:
        # 这里指定将configmap中的配置挂载到/usr/local/filebeat/filebeat.yml
        - name: config
          mountPath: /usr/local/filebeat/filebeat.yml
          readOnly: true
          subPath: filebeat.yml
      volumes:
      # 这里的ConfigMap配置和上面的一样
      - name: config
        configMap:
          name: filebeat-configmap
```

> **遇到的问题：**  
>
> * 制作合并镜像时一定要将工作目录设置为根路径，否则App日志目录会存放在应用启动时的相对路径下，这可能会导致filebeat无法读到正确的日志文件路径，这里将工作目录设为/，然后再根路径下启动springboot应用，则日志会存在于根路径下的logs"目录"下；  
> * 注意基础镜像选择问题，alpine版本中无法运行filebeat；  
> * 注意一个容器中只能有一个前台进程运行，且必须要有一个前台进程。  

#### 3.7.1.4 Packetbeat    

下面示例将packetbeat配置到kube-system名称空间下，而各个名称空间之间的资源是相互隔离的，所以为了能正常创建Pod，发送数据到default名称空间的ES中存储，并和Kibana之间进行通信创建packetbeat自带的图表模板，在此通过创建External Service来实现跨名称空间的服务通信，相关配置如下。  

`es-svc-en.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch
  namespace: kube-system
spec:
  #ports:
  #- name: http
    #port: 9200
    #protocol: TCP
  #- name: transpor
    #port: 9300
    #protocol: TCP
  # 类型为ExternalName，注意externalName的书写规则为：服务名称.服务所在名称空间.svc.cluster.local
  type: ExternalName
  externalName: elasticsearch.default.svc.cluster.local
```

`kibana-svc-en.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: kibana
  namespace: kube-system
spec:
  #ports:
  #- name: http
    #port: 5601
  type: ExternalName
  externalName: kibana.default.svc.cluster.local
```

> **遇到的问题：**  
>
> * externalName的值很特别，尝试了很多次才研究出正确写法，直接写服务名称，或者服务名称.名称空间，会导致服务调用不通而在beat启动时报错。

* `packetbeat-cm.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: packetbeat-configmap
  namespace: kube-system
data:
  packetbeat.yml: |-
    # Network device
    packetbeat.interfaces.device: any

    # Flows
    packetbeat.flows:
      timeout: 30s
      period: 10s

    # Transaction Protocols
    packetbeat.protocols:
    - type: icmp
      enabled: true

    - type: amqp
      ports: [5672]

    - type: cassandra
      ports: [9042]

    - type: dns
      ports: [53]
      include_authorities: true
      #include_additionals: true
    # 配置监听http协议的8666和8080端口
    - type: http
      ports: [8666,8080]
      real_ip_header: "X-Forwarder-For"

    - type: memcache
      ports: [11211]

    - type: mysql
      ports: [3306]

    - type: pgsql
      ports: [5432]

    - type: redis
      ports: [6379]

    - type: thrift
      ports: [9090]

    - type: mongodb
      ports: [27017]

    - type: nfs
      ports: [2049]

    - type: tls
      ports: [443]

    # General
    #name: packetbeat-k8s
    tags: ["k8s-beat"]

    # Dashboards
    setup.dashboards.enabled: true
    #setup.dashboards.url

    # Kibana    
    setup.kibana:
      host: ${KIBANA_HOST}:${KIBANA_PORT}
    
    # Outputs
    ## Elastisearch output
    output.elasticsearch:
      hosts: ['${ELASTICSEARCH_HOST}:${ELASTICSEARCH_PORT}']
      username: ${ELASTICSEARCH_USERNAME}
      password: ${ELASTICSEARCH_PASSWORD}
```

* `packetbeat-ds.yaml`

```yaml
# 指定类型为DaemonSet，这样会在各个k8s节点上都会创建一个Pod
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: packetbeat
  # 这里可以设置所属namespace的名称
  namespace: kube-system
  labels:
    k8s-beat: packetbeat
spec:
  template:
    metadata:
      labels:
        k8s-beat: packetbeat
    spec:
      terminationGracePeriodSeconds: 30	# 优雅关闭
      hostNetwork: true	# 使用主机网络模式
      dnsPolicy: ClusterFirstWithHostNet	# 使用k8s的dns
      containers:
      - name: packetbeat
        image: docker.elastic.co/beats/packetbeat:6.3.0
        #args: [
          #"-c", "/etc/packetbeat.yml",
          #"-e",
        #]
        # 开启相关权限
        securityContext:
          runAsUser: 0
          capabilities:
            add:
            - NET_ADMIN
        env:
        - name: ELASTICSEARCH_HOST
          value: elasticsearch
        - name: ELASTICSEARCH_PORT
          value: "9200"
        - name: ELASTICSEARCH_USERNAME
          value: elastic
        - name: ELASTICSEARCH_PASSWORD
          value: changeme
        - name: KIBANA_HOST
          value: kibana
        - name: KIBANA_PORT
          value: "5601"
        resources:
          limits:
            memory: 200Mi
          requests:
            cpu: 100m
            memory: 100Mi
        volumeMounts:
        - name: timezone
          mountPath: /etc/localtime
        - name: config
          # 两种挂载方式都可以实现按configmap中的配置启动packetbeat，如果是mountPath: /etc/packetbeat.yml，则需要配合上面注释的args使用
          #mountPath: /etc/packetbeat.yml
          mountPath: /usr/share/packetbeat/packetbeat.yml
          readOnly: true
          subPath: packetbeat.yml
        - name: data
          mountPath: /usr/share/packetbeat/data
      volumes:
      - name: timezone
        hostPath:
          path: /etc/localtime 
      - name: config
        configMap:
          name: packetbeat-configmap
      - name: data
        hostPath:
          path: /ebk/packetbeat/data
```

> **遇到的问题：**  
>
> * 需要配置hostNetwork: true和capabilities.add NET_ADMIN，否则packetbeat启动会报错。

```shell
# 按顺序启动各个资源
kubectl create -f es-svc-en.yaml
kubectl create -f kibana-svc-en.yaml
kubectl create -f packetbeat-cm.yaml
kubectl create -f packetbeat-ds.yaml

# 查看各资源情况可使用下面命令
kubectl get svc --namespace=kube-system
kubectl get cm --namespace=kube-system
kubectl get pod --namespace=kube-system
```

#### 3.7.1.5 Metricbeat  

同样示例将metricbeat放入kube-system名称空间下，所以需要配合Packetbeat小节中的External Service部署，另外由于要监控kubernetes资源，在这里需要配合部署kube-state-metrics服务，且该服务必须配置相关权限才能访问k8s的相关api获取数据。  

##### 3.7.1.5.1 部署kube-state-metrics    

* `kube-state-metrics-sa.yaml`

```yaml
# 这里为ServiceAccount类型，用于安全认证配置
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kube-state-metrics
  namespace: kube-system
```

* `kube-state-metrics-role.yaml`

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  namespace: kube-system
  name: kube-state-metrics
# 可配置多组规则
rules:
# 这里配置默认可查询一下resources
- apiGroups: [""]
  resources:
  - configmaps
  - secrets
  - nodes
  - pods
  - services
  - replicationcontrollers
  - resourcequotas
  - limitranges
  - persistentvolumeclaims
  - persistentvolumes
  - namespaces
  - endpoints
  - events
  # 配置可进行get/list/watch等操作
  verbs: ["get","list","watch"]
- apiGroups: ["extensions"]
  resources:
  - daemonsets
  - deployments
  - replicasets
  verbs: ["list","watch"]
- apiGroups: ["apps"]
  resources:
  - statefulsets
  verbs: ["list","watch"]
- apiGroups: ["batch"]
  resources:
  - cronjobs
  - jobs
  verbs: ["list","watch"]
- apiGroups: ["autoscaling"]
  resources:
  - horizontalpodautoscalers
  verbs: ["list","watch"]
```

* `kube-state-metrics-role-binding.yaml`

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kube-state-metrics
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kube-state-metrics
subjects:
- kind: ServiceAccount
  name: kube-state-metrics
  namespace: kube-system
```

* `kube-state-metrics-dep.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kube-state-metrics
  namespace: kube-system
spec:
  selector:
    matchLabels:
      k8s-app: kube-state-metrics
  replicas: 1
  template:
    metadata:
      labels:
        k8s-app: kube-state-metrics
    spec:
      # 指定使用名为kube-state-metrics的serviceAccount权限
      serviceAccountName: kube-state-metrics
      containers:
      - name: kube-state-metrics
        # 这个镜像是官方推荐的
        image: quay.io/coreos/kube-state-metrics:v1.3.1
        ports:
        - name: http-metrics
          containerPort: 8080
        - name: telemetry
          containerPort: 8081
        readinessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 5
          timeoutSeconds: 5
      - name: addon-resizer
        # 下面注释的部分为官方示例的镜像，但由于墙的问题而无法下载，所以在此使用了另一个私人镜像代替
        #image: k8s.gcr.io/addon-resizer:1.7
        # 注意这里必须是1.7版本，否则该容器会无法运行
        image: quay.io/google-containers/addon-resizer:1.7
        resources:
          limits:
            cpu: 100m
            memory: 30Mi
          requests:
            cpu: 100m
            memory: 30Mi
        env:
        - name: MY_POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: MY_POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        command:
          - /pod_nanny
          - --container=kube-state-metrics
          - --cpu=100m
          - --extra-cpu=1m
          - --memory=100Mi
          - --extra-memory=2Mi
          - --threshold=5
          - --deployment=kube-state-metrics
```

* `kube-state-metrics-svc.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: kube-state-metrics
  namespace: kube-system
  labels:
    k8s-app: kube-state-metrics
spec:
  selector:
    k8s-app: kube-state-metrics
  ports:
  - name: http-metrics
    port: 8080
    targetPort: http-metrics
    protocol: TCP
  - name: telemetry
    port: 8081
    targetPort: telemetry
    protocol: TCP
```

> **遇到的问题：**  
>
> * 必须指定并创建ServiceAccount相关权限资源，否则kube-state-metrics容器会报错，无法获取到k8s的数据；  
> * addon-resizer镜像必须使用1.7版本，否则该容器会无法启动。  

```shell
# 按顺序启动各资源
kubectl create -f kube-state-metrics-sa.yaml
kubectl create -f kube-state-metrics-role.yaml
kubectl create -f kube-state-metrics-role-binding.yaml
kubectl create -f kube-state-metrics-dep.yaml
kubectl create -f kube-state-metrics-svc.yaml
```

##### 3.7.1.5.2 部署metricbeat    

* `metricbeat-cm.yaml`

```yaml
# 下面配置一些通用项
apiVersion: v1
kind: ConfigMap
metadata:
  name: metricbeat-configmap
  namespace: kube-system
data:
  metricbeat.yml: |-
    # Modules configuration
    metricbeat.config.modules:
      path: ${path.config}/modules.d/*.yml
      reload.enabled: false
      #reload.period: 10s

    # General
    #name: metricbeat #不能配，否则默认system overview仪表板不能按宿主机名称分类显示 
    tags: ["k8s-beat"]

    # Dashboards
    setup.dashboards.enabled: true
    #setup.dashboards.url:

    # Kibana    
    setup.kibana:
      host: ${KIBANA_HOST}:${KIBANA_PORT}
    
    # Outputs
    ## Elastisearch output
    output.elasticsearch:
      hosts: ['${ELASTICSEARCH_HOST}:${ELASTICSEARCH_PORT}']
      username: ${ELASTICSEARCH_USERNAME}
      password: ${ELASTICSEARCH_PASSWORD}
```

* `metricbeat-modules-cm.yaml`

```yaml
# 下面针对system/docker/kubernetes使用多个独立的yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: metricbeat-modules-configmap
  namespace: kube-system
data:
  # 配置监控系统资源
  system.yml: |-
    - module: system
      period: 10s
      metricsets:
        - cpu
        - load
        - memory
        - network
        - process
        - process_summary
        - core
        - diskio
        - socket
      processes: ['.*']
      process.include_top_n:
        by_cpu: 5
        by_memory: 5

    - module: system
      period: 1m
      metricsets:
        - filesystem
        - fsstat
      processors:
      - drop_event.when.regexp:
          system.filesystem.mount_point: '^/(sys|cgroup|proc|dev|etc|host|lib)($|/)'

    - module: system
      period: 15m
      metricsets:
        - uptime
  
  # 配置健康kubernetes资源
  kubernetes.yml: |-
    # 来自kubelet的node指标
    - module: kubernetes
      metricsets:
        - node
        - system
        - pod
        - container
        - volume
      period: 10s
      # 由于目前环境中kubelet的10255端口未开发，所以上面配置暂时无法收集到数据
      hosts: ["localhost:10255"]

    # 来自kube-state-metrics的service指标,需要配合kube-state-metrics使用才行
    - module: kubernetes
      enabled: true
      metricsets:
        - state_node
        - state_deployment
        - state_replicaset
        - state_pod
        - state_container
      period: 10s
      hosts: ["kube-state-metrics:8080"]

    # k8s的事件，由于该数据来源于查询k8s的API，所以需要配置ServiceAccount相关权限才可用
    - module: kubernetes
      enabled: true
      metricsets:
        - event 
  
  # 配置监控docker资源
  docker.yml: |-
    - module: docker
      metricsets:
        - "container"
        - "cpu"
        - "diskio"
        - "healthcheck"
        - "info"
        - "image"
        - "memory"
        - "network"
      hosts: ["unix:///var/run/docker.sock"]
      period: 10s
      enabled: true

      # 用_替换.
      labels.dedot: true
```

* `metricbeat-ds.yaml`

```yaml
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: metricbeat
  namespace: kube-system
  labels:
    k8s-beat: metricbeat
spec:
  template:
    metadata:
      labels:
        k8s-beat: metricbeat
    spec:
      # 配置使用kube-state-metrics的相关权限设置
      serviceAccountName: kube-state-metrics
      terminationGracePeriodSeconds: 30	# 优雅关闭
      hostNetwork: true	# 使用主机网络模式
      dnsPolicy: ClusterFirstWithHostNet	# 使用k8s的dns
      containers:
      - name: metricbeat
        image: docker.elastic.co/beats/metricbeat:6.3.0
        args: [
          "-c", "/etc/metricbeat.yml",
          "-e",
          "-system.hostfs=/hostfs",
        ]
        securityContext:
          runAsUser: 0
        env:
        - name: ELASTICSEARCH_HOST
          value: elasticsearch
        - name: ELASTICSEARCH_PORT
          value: "9200"
        - name: ELASTICSEARCH_USERNAME
          value: elastic
        - name: ELASTICSEARCH_PASSWORD
          value: changeme
        - name: KIBANA_HOST
          value: kibana
        - name: KIBANA_PORT
          value: "5601"
        resources:
          limits:
            memory: 200Mi
          requests:
            cpu: 200m
            memory: 100Mi
        volumeMounts:
        - name: timezone
          mountPath: /etc/localtime
        - name: config
          mountPath: /etc/metricbeat.yml
          readOnly: true
          subPath: metricbeat.yml
        - name: modules
          mountPath: /usr/share/metricbeat/modules.d
          readOnly: true
        - name: dockersock
          mountPath: /var/run/docker.sock
        - name: proc
          mountPath: /hostfs/proc
          readOnly: true
        - name: cgroup
          mountPath: /hostfs/sys/fs/cgroup
          readOnly: true
        - name: data
          mountPath: /usr/share/metricbeat/data
      volumes:
      - name: timezone
        hostPath:
          path: /etc/localtime
      - name: proc
        hostPath:
          path: /proc
      - name: cgroup
        hostPath:
          path: /sys/fs/cgroup
      - name: dockersock
        hostPath:
          path: /var/run/docker.sock 
      - name: config
        configMap:
          name: metricbeat-configmap
      - name: modules
        configMap:
          name: metricbeat-modules-configmap
      - name: data
        hostPath:
          path: /ebk/metricbeat/data
```

> **遇到的问题：**  
>
> * `metricbeat-modules-cm.yaml` 中的格式有问题导致无法获取到指标数据；  
> * `metricbeat-cm.yaml` 中配置了name: metricbeat导致kibana中的系统资源仪表板中看不到各个主机的指标信息，其未按各主机的hostname进行分组；  
> * 未部署kube-state-metrics导致无法监控k8s相关资源；  
> * 部署了kube-state-metrics服务，但未配置ServiceAccount导致无法获取K8S相关资源；  
> * `metricbeat-ds.yaml` 中未配置serviceAccountName导致无法获取到k8s的event事件数据；  
> * 配置了hosts: ["localhost:10255"]，但不生效，相关数据未收集到，后来发现是kubelet的10255端口未开放，此需要研究rancher的配置使用，此问题暂未能解决。  

```shell
# 按顺序启动各资源
kubectl create -f metricbeat-cm.yaml
kubectl create -f metricbeat-modules-cm.yaml
kubectl create -f metricbeat-ds.yaml
```

