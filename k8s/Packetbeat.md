## 7.3 Packetbeat监控方案探索  

### 7.3.1 一个Pod内多个容器    

这里示例将Packetbeat和App应用分为两个容器部署在一个Pod内，然后部署3份并提供一个Service提供统一的访问入口，相关部署文件如下：  

* `packetbeat-multi-cm.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: packetbeat-multi-configmap
data:
  packetbeat.yml: |-
    # Network device
    packetbeat.interfaces.device: any

    # Flows
    packetbeat.flows:
      timeout: 30s
      #period: 10s
      # 默认采集周期为10s,这里设置为-1s表示不采集中间流量报告，会去掉很多无用数据
      period: -1s

    # Transaction Protocols
    packetbeat.protocols:
    - type: http
      # 这里配置监听同Pod内的应用端口，这里的协议配置的是http，除此之外还可以配置很多其它协议，如pgsql
      ports: [8666,8888,7777]
      real_ip_header: "X-Forwarder-For"

    # General
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

* `packetbeat-multi-dep.yaml`

```yaml
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: app-beat-multi
  labels:
    app-beat: app-beat-multi
spec:
  replicas: 3
  template:
    metadata:
      labels:
        app-beat: app-beat-multi
    spec:
      terminationGracePeriodSeconds: 30
      containers:
      - name: spring-boot-filebeat
        image: 172.18.3.108/ebk/spring-boot-filebeat:v1
        imagePullPolicy: Always
        ports:
        - containerPort: 8666
        volumeMounts:
        - name: shared-log
          mountPath: /logs
        - name: timezone
          mountPath: /etc/localtime

      - name: filebeat
        image: docker.elastic.co/beats/filebeat:6.3.0
        args: [
          "-c", "/etc/filebeat.yml",
          "-e",
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
        volumeMounts:
        - name: shared-log
          mountPath: /logs
        - name: timezone
          mountPath: /etc/localtime
        - name: filebeat-config
          mountPath: /etc/filebeat.yml
          readOnly: true
          subPath: filebeat.yml
        - name: filebeat-data
          mountPath: /usr/share/filebeat/data

      - name: packetbeat
        image: docker.elastic.co/beats/packetbeat:6.3.0
        args: [
          "-c", "/etc/packetbeat.yml",
          "-e",
        ]
        # 注意需要开启权限，否则packetbeat无法启动
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
        - name: packetbeat-config
          mountPath: /etc/packetbeat.yml
          readOnly: true
          subPath: packetbeat.yml
        - name: packetbeat-data
          mountPath: /usr/share/packetbeat/data

      volumes:
      - name: shared-log
        emptyDir: {}
      - name: timezone
        hostPath:
          path: /etc/localtime
      - name: filebeat-data
        hostPath:
          path: /ebk/filebeat/data
      - name: packetbeat-data
        hostPath:
          path: /ebk/packetbeat/data
      - name: filebeat-config
        configMap:
          name: filebeat-configmap
      - name: packetbeat-config
        configMap:
          name: packetbeat-multi-configmap
```

* `packetbeat-multi-svc.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: app-beat-multi
  labels:
    app-beat: app-beat-multi
spec:
  selector:
    app-beat: app-beat-multi
  ports:
    - port: 8888
      targetPort: 8666
```

```shell
# 按顺序创建资源
kubectl create -f packetbeat-multi-cm.yaml
kubectl create -f packetbeat-multi-dep.yaml
kubectl create -f packetbeat-multi-svc.yaml
# 如要删除资源，可执行下面命令
kubectl delete -f packetbeat-multi-svc.yaml
kubectl delete -f packetbeat-multi-dep.yaml
kubectl delete -f packetbeat-multi-cm.yaml
# 查看Pod和Service的状态
kubectl get pod,svc
```

下图为部署了两个APP应用集群后的流量监控图，因为没有大量服务调用请求，所以这里大部分流量都是各Pod内的beat采集数据发送到ES集群中存储产生的。采用这种部署方案的好处就是，不管是直接访问Servcie IP调用接口还是直接请求指定Pod IP调用接口，这里都不会有流量“重复”统计的可能，且对API调用次数的统计也不会有重复统计的问题。  

![1531230678269](images/1531230678269.png)  

### 7.3.2 一个Pod内一个容器    

这里示例将Packetbeat和应用放在一起制作成一个镜像，然后创建对应的应用集群，相关部署配置文件如下：  

```shell
# 首先我们可以先将packetbeat的二进制压缩包下载下来，然后编写Dockerfile制作镜像
wget -c https://artifacts.elastic.co/downloads/beats/packetbeat/packetbeat-6.3.0-linux-x86_64.tar.gz
```

* `Dockerfile`

```dockerfile
# 使用压缩版openjdk镜像做基础镜像
FROM openjdk:8-jdk-slim
# 添加二进制包到指定目录，相应的包要放在和Dockerfile同级目录下
ADD filebeat-6.3.0-linux-x86_64.tar.gz /usr/local/
ADD packetbeat-6.3.0-linux-x86_64.tar.gz /usr/local/
# 复制容器运行时的启动脚本
COPY docker-entrypoint /
# 解压beat包并进行所属用户修改等操作
RUN mv /usr/local/filebeat-6.3.0-linux-x86_64 /usr/local/filebeat && \
    cd /usr/local/filebeat && \
    mkdir data logs && \
    chown -R root:root . && \
    mv /usr/local/packetbeat-6.3.0-linux-x86_64 /usr/local/packetbeat && \
    cd /usr/local/packetbeat && \
    mkdir data logs && \
    chown -R root:root . && \
    chmod 755 /docker-entrypoint
# 添加应用jar包，并暴露端口
ADD xseed-system1-backend-2.0.0.jar /app.jar
EXPOSE 8666
# 设置工作目录
WORKDIR /
ENTRYPOINT ["/docker-entrypoint"]
```

* `docker-entrypoint`

```shell
#! /bin/bash
exec nohup /usr/local/filebeat/filebeat -e -c /usr/local/filebeat/filebeat.yml -d "publish" 2>/dev/null &
exec nohup /usr/local/packetbeat/packetbeat -e -c /usr/local/packetbeat/packetbeat.yml -d "publish" 2>/dev/null &
exec java -Djava.security.egd=file:/dev/./urandom -jar /app.jar 
```

* `packetbeat-multi-inone-dep.yaml`

```yaml
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: app-beat-multi-inone
  labels:
    app-beat: app-beat-multi-inone
spec:
  replicas: 3
  template:
    metadata:
      labels:
        app-beat: app-beat-multi-inone
    spec:
      terminationGracePeriodSeconds: 30 #优雅关闭
      containers:
      - name: app-beat-multi-inone
        image: 172.18.3.108/ebk/app-beat-multi-inone-slim:v1 
        #imagePullPolicy: Always
        securityContext:
          runAsUser: 0
          # 下面是可选的
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
        ports:
        - containerPort: 8666
        volumeMounts:
        - name: filebeat-config
          mountPath: /usr/local/filebeat/filebeat.yml
          readOnly: true
          subPath: filebeat.yml
        - name: packetbeat-config
          mountPath: /usr/local/packetbeat/packetbeat.yml
          readOnly: true
          subPath: packetbeat.yml
      volumes:
      - name: filebeat-config
        configMap:
          name: filebeat-configmap
      # 注意这里借用了上面的ConfigMap配置，如果要单独配置，请重新编写并创建一个ConfigMap
      - name: packetbeat-config
        configMap:
          name: packetbeat-multi-configmap
```

* `packetbeat-multi-inone-svc.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: app-beat-multi-inone
  labels:
    app-beat: app-beat-multi-inone
spec:
  selector:
    app-beat: app-beat-multi-inone
  ports:
    - port: 8888
      targetPort: 8666
```

```shell
###### 下面示例创建镜像到部署Pod和Service的全过程 ######
# 在Dockerfile目录下创建名为my/app-beat-multi-inone的镜像
docker build -t my/app-beat-multi-inone .
# 登陆Harbor仓库,然后输入用户名和密码
docker login 172.18.3.108
# 给镜像打上tag并重命名为172.18.3.108/ebk/app-beat-multi-inone-slim，接着推送到仓库
docker tag my/app-beat-multi-inone 172.18.3.108/ebk/app-beat-multi-inone-slim:v1
docker push 172.18.3.108/ebk/app-beat-multi-inone-slim:v1

# 按顺序创建资源
# 这里的前提是借用了上面的packetbeat-multi-cm.yaml的配置，否则需要自己编写一个ConfigMap配置，然后先创建ConfigMap，再创建下面的Pod和Service
kubectl create -f packetbeat-multi-inone-dep.yaml
kubectl create -f packetbeat-multi-inone-svc.yaml
```

按上面的配置创建好各个资源后，我们可以看到Kibana流量监控图表中多了3个刚创建的Pod相关流量，如下：

![1531289398117](images/1531289398117.png)  

### 7.3.3 额外添加Host流量监控   

#### 7.3.3.1 部署Pod    

* `packetbeat-host-cm.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: packetbeat-host-configmap
data:
  packetbeat.yml: |-
    # Network device
    packetbeat.interfaces.device: any

    # Flows
    packetbeat.flows:
      timeout: 30s
      #period: 10s
      # 默认采集周期为10s,这里设置为-1s表示不采集中间流量报告，会去掉很多无用数据
      period: -1s

    # Transaction Protocols
    packetbeat.protocols:
    # 如果要监控Host主机流量，那么建议仅开启流量采集一项功能，其他的如HTTP协议端口监听等都不要开启，否则统计API调用次数时会存在重复统计问题
    #- type: http
      #ports: [8666,8888,7777]
      #real_ip_header: "X-Forwarder-For"

    # General
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

* `packetbeat-host-ds.yaml`  

```yaml
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: packetbeat-host
  labels:
    k8s-beat: packetbeat-host
spec:
  template:
    metadata:
      labels:
        k8s-beat: packetbeat-host
    spec:
      terminationGracePeriodSeconds: 30	#优雅关闭
      hostNetwork: true	# 使用主机网络模式
      dnsPolicy: ClusterFirstWithHostNet	# 使用k8s的dns
      containers:
      - name: packetbeat
        image: docker.elastic.co/beats/packetbeat:6.3.0
        args: [
          "-c", "/etc/packetbeat.yml",
          "-e",
        ]
        # 开启网络检测权限
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
          mountPath: /etc/packetbeat.yml
          readOnly: true
          subPath: packetbeat.yml
      volumes:
      - name: timezone
        hostPath:
          path: /etc/localtime 
      - name: config
        configMap:
          name: packetbeat-host-configmap
```

```shell
# 按顺序创建资源
kubectl create -f packetbeat-host-cm.yaml
kubectl create -f packetbeat-host-ds.yaml
# 如要删除资源，可使用下面命令
kubectl delete -f packetbeat-host-ds.yaml
kubectl delete -f packetbeat-host-cm.yaml
```

#### 7.3.3.2 Kibana监控  

部署完成后可以在Kibana的Packetbeat Flows页面看到Host主机IP相关的流量，详见下图。  

![1531223035355](images/1531223035355.png)  

下面我们在主机hakugei-1上访问主机hakugei-2上的业务应用的一个API接口，然后对数据进行过滤后会看到下面3条流量数据详情：  

* 第一条数据的`source.stats.net_bytes_total`值为1503，这是主机hakugei-2上的packetbeat采集到的流量数据；  
* 第二条数据是主机hakugei-1上的packetbeat采集到的流量数据，`source.stats.net_bytes_total`值为501；  
* 第三条数据是主机hakugei-2上真正被请求的应用Pod内的packetbeat采集到的流量数据，`source.stats.net_bytes_total`值为501。  

```shell
# 在主机hakugei-1上直接请求主机hakugei-2上应用Pod内的API接口
root@hakugei-1:~# curl 10.42.0.122:8666/hello
```

![1531218445717](images/1531218445717.png) 

![1531218537858](images/1531218537858.png)  

![1531218632398](images/1531218632398.png)  

> 从这些数值我们可以简单发现主机hakugei-2上的packetbeat采集到的流量数据（1501）刚好是应用Pod内packetbeat采集到的流量数据（501）的3倍，对于这里的原因解释需要深入研究Flannel网络原理及Packetbeat采集原理才能给出，这里可能存在“重复”统计的问题，所以对于1501可能并不是我们想要的或关注的。下面是对流量数据统计过程的一个简单分析（供参考），此分析不一定正确，仅为个人思考总结得出：  

下面是OpenShift容器平台中Flannel网络的数据流图（在k8s中的数据流是类似的），此图较清晰的表达了一个容器到另一个容器的数据流过程，大概的过程都是通过路由表找到对应的flannel虚拟网卡，然后通过flanneld找到目标主机，再通过目标主机上的flannel虚拟网卡进行数据转发：
![27204300](images/27204300.png)

通过对上图数据流过程的理解，接下来具体分析示例流量的数据流：首先在hakugei-1主机上curl 10.42.0.122，其数据包转发过程如下图，所以就产生了上面第二条数据记录（src: 10.42.2.0 --> dest: 10.42.0.122, 数据大小501字节）![1531364156245](images/1531364156245.png)  

接着数据包会被再封装后发到hakugei-2上，相关过程分析如下，这也就产生了第一条数据记录（src:10.42.2.0 --> dest:10.42.0.122,数据大小1503字节）

![1531365527543](images/1531365527543.png)  

最后由应用Pod内的packetbeat采集到来自src:10.42.2.0的数据包，大小501字节，整个过程中src都是hakugei-1上的flannel.1的IP。数据记录详情见上面第三张图。

### 7.3.4 部署方案简单对比  

> * 在每个主机上部署一个全局Packetbeat还是在每个应用Pod内独立部署：  
>   - 全局Packetbeat会监控各种流量，其中可能很多流量不是我们所关心的，也可能存在很多“重复”流量；但这种方式占用系统资源相比独立部署要少。
>   - 独立部署可以精准监控我们关心的业务Pod上的流量，且可以精准监控该Pod上的各种协议端口访问数据；但如果业务Pod很多的情况下，这种部署方式对系统资源的占用显然会多不少。
>   - 个人觉得这个主要看监控需求，在被监控Pod数量不多的情况下可以考虑独立部署。  
> * 一个Pod内多个容器和一个Pod内一个容器的主要差异为：  
>   + 镜像大小差异，多个容器的总大小要大于一个容器的总大小，上面示例中的大小差异约300+M；  
>   + 集中在一个容器内可能给滚动升级和运行维护带来不便；  
>   + 个人觉得在存储资源较丰富的情况下应优先考虑分容器部署。

| 编号 | 方案                                                 | 优点                                              | 缺点                                                     |
| ---- | ---------------------------------------------------- | ------------------------------------------------- | -------------------------------------------------------- |
| 1    | 每个app的镜像中集成网络收集组件                      | 可以为每个app自定义采集配置，yaml文件无须特别配置 | 强耦合，不方便app和采集组件的升级和维护                  |
| 2    | 单独创建一个网络收集组件，跟app容器运行在同一个pod中 | 低耦合，扩展性强，方便维护和升级                  | 需要在yaml中添加一些特别配置，多个容器的大小不能压缩     |
| 3    | 每台主机上单独部署一个网络收集Pod                    | 完全解耦，资源占用少，管理最方便                  | 需要考虑统一的采集配置，可能存在不是我们想要的“重复”流量 |




