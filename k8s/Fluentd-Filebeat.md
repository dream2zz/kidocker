## 7.4 日志监控进阶  

日志记录的目的主要是为了能够分析出：哪位用户---在什么时间---访问哪个服务---调用哪个方法---传入什么参数---得到什么结果，这些基本都可以在应用日志记录时通过添加一些信息来达到可追溯的目的。

而对于“访问哪个服务”的问题，这里也可以通过一些日志组件提供的功能来实现日志区分，接下来我们就分别使用Fluentd和Filebeat日志组件，解决不同部署（基于k8s+docker环境）方案下的日志区分问题，希望通过这种带着问题去探索解决方案的方式让大家对这两款日志组件的区别有一个初步的认识。

### 7.4.1 Fluentd日志监控  

Fluentd是一个完全免费且完全开源的日志收集器，拥有灵活的插件系统，目前有500多个社区贡献的插件来连接数十个数据源和数据输出。它是用C语言和Ruby组合编写的，只需要很少的系统资源，其支持基于内存和文件的缓冲，以防止节点间数据丢失，其还支持强大的故障转移功能，支持高可用性配置。

#### 7.4.1.1 应用日志之局部监控    

下面示例在同一个Pod中部署app和fluentd，这里主要是通过app自身在记录日志时添加一些信息来实现区分：

* 修改logback配置文件，日志中扩展添加“主机”名和“主机”IP两个字段  

```xml
# 下面配置截取于种子工程中的logback-spring.xml
<!-- 配置自定义扩展信息类,该类主要扩展获取主机IP地址 -->
<conversionRule conversionWord="ip" converterClass="com.gsafety.xseed.system1.backend.configs.IPLogConfig" />

<appender name="JSON_FILE" class="ch.qos.logback.core.rolling.RollingFileAppender">
    ...
    <pattern>
        <pattern>
            <!-- 添加hostName和hostIP两个字段，其中ip来源于上面的自定义类 -->
            {
            "hostName": "${HOSTNAME}",
            "hostIP": "%ip",
            "severity": "%level",
            "service": "${springAppName:-}",
            "thread": "%thread",
            "logger": "%logger",
            "message": "%message"
            }
        </pattern>
    </pattern>
 ...
</appender>
```

```java
package com.gsafety.xseed.system1.backend.configs;

import ch.qos.logback.classic.pattern.ClassicConverter;
import ch.qos.logback.classic.spi.ILoggingEvent;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.net.InetAddress;
import java.net.NetworkInterface;
import java.util.Enumeration;

public class IPLogConfig extends ClassicConverter {
    private static final Logger log = LoggerFactory.getLogger(IPLogConfig.class);

    @Override
    public String convert(ILoggingEvent event) {
        return getLocalHostLANAddress() == null ? null : getLocalHostLANAddress().getHostAddress();
    }
    
	/**
     * 筛选并返回一个较佳的InetAddress对象
     * @return
     */
    private static InetAddress getLocalHostLANAddress() {
        InetAddress candidateAddress = null;
        try {
            Enumeration interfaces = NetworkInterface.getNetworkInterfaces();
            if (interfaces != null) {
                while (interfaces.hasMoreElements()) {
                    NetworkInterface networkInterface = (NetworkInterface) interfaces.nextElement();
                    Enumeration<InetAddress> inetAddresses = networkInterface.getInetAddresses();
                    while (inetAddresses.hasMoreElements()) {
                        InetAddress inetAddress = inetAddresses.nextElement();
                        if (!inetAddress.isLoopbackAddress()) {
                            if (inetAddress.isSiteLocalAddress()) {
                                return inetAddress;
                            } else if (candidateAddress == null) {
                                candidateAddress = inetAddress;
                            }
                        }
                    }
                }
            }

            if (candidateAddress != null) {
                return candidateAddress;
            }

            return InetAddress.getLocalHost();
        } catch (Exception e) {
//            e.printStackTrace();
            log.error("Failed to get LAN address: ", e);
        }
        return candidateAddress;
    }
}

```

* 编写Yaml采集日志并输出到ES中，`fluentd-app-es-dep-all.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentd-es-configmap
data:
  fluent.conf: |-
    # 配置导入指定路径指定规则名称的所有模块配置
    @include /etc/fluent/config.d/*.conf	
    # 配置不收集fluentd自己的日志，避免死循环
    <match fluent.**>
      @type null
    </match>

    # match指令用于确定输出目标，**表示匹配任意输入
    <match **>
      @type elasticsearch
      @id out_es
      log_level info
      include_tag_key true
      host "#{ENV['FLUENT_ELASTICSEARCH_HOST']}"
      port "#{ENV['FLUENT_ELASTICSEARCH_PORT']}"
      scheme "#{ENV['FLUENT_ELASTICSEARCH_SCHEME'] || 'http'}"
      ssl_verify "#{ENV['FLUENT_ELASTICSEARCH_SSL_VERIFY'] || 'true'}"
      user "#{ENV['FLUENT_ELASTICSEARCH_USER']}"
      password "#{ENV['FLUENT_ELASTICSEARCH_PASSWORD']}"
      reload_connections "#{ENV['FLUENT_ELASTICSEARCH_RELOAD_CONNECTIONS'] || 'true'}"
      logstash_prefix "#{ENV['FLUENT_ELASTICSEARCH_LOGSTASH_PREFIX'] || 'logstash'}"
      logstash_format true
      <buffer>
        flush_thread_count 8
        flush_interval 5s
        chunk_limit_size 2M
        queue_limit_length 32
        retry_max_interval 30
        retry_forever true
      </buffer>
    </match>
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentd-modules-es-configmap
data:
  app.input.conf: |-
    # source指令用于确认输入源
    <source>
      # 该输入配置的唯一名称
      @id fluentd-app.log
      # 指定插件类型
      @type tail
      # 指定输入位置
      path /logs/*.json
      # (官方强烈推荐配置此项)fluentd会将上次读取的位置记录到此文件中
      pos_file /logs/fluentd-app.log.pos
      # 为该输入源添加标签，便于让match指令按一定规则确定输出源
      tag app.k8s.*
      # 开始从文件头部读取日志，而不是底部
      read_from_head true
      <parse>
        @type json
        time_format %Y-%m-%dT%H:%M:%S.%NZ
      </parse>
    </source>
---
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: fluentd-app-logging
  labels:
    k8s-app: fluentd-app-logging
spec:
  replicas: 3
  template:
    metadata:
      labels:
        k8s-app: fluentd-app-logging
    spec:
      containers:
      - name: spring-boot-fluentd
        image: 172.18.3.108/ebk/spring-boot-log-host:v1 
        #imagePullPolicy: Always
        ports:
        - containerPort: 8666
        volumeMounts:
        - name: shared-log
          mountPath: /logs
        - name: timezone
          mountPath: /etc/localtime

      - name: fluentd
        image: fluent/fluentd-kubernetes-daemonset:v1.2.2-debian-elasticsearch
        securityContext:
          runAsUser: 0
        env:
          - name: FLUENT_ELASTICSEARCH_HOST
            value: "elasticsearch"
          - name: FLUENT_ELASTICSEARCH_PORT
            value: "9200"
          - name: FLUENT_ELASTICSEARCH_SCHEME
            value: "http"
          - name: FLUENT_ELASTICSEARCH_SSL_VERIFY
            value: "false"
          - name: FLUENT_ELASTICSEARCH_USER
            value: "elastic"
          - name: FLUENT_ELASTICSEARCH_PASSWORD
            value: "changeme"
          - name: FLUENT_ELASTICSEARCH_RELOAD_CONNECTIONS
            value: "true"
          # 用于配置在es中的索引名称前缀
          - name: FLUENT_ELASTICSEARCH_LOGSTASH_PREFIX
            value: "logstash"
        resources:
          limits:
            memory: 200Mi
          requests:
            cpu: 100m
            memory: 200Mi
        volumeMounts:
        - name: shared-log
          mountPath: /logs
        - name: timezone
          mountPath: /etc/localtime
        - name: fluentd-config
          mountPath: /fluentd/etc/
          readOnly: true
        - name: fluentd-modules-config
          mountPath: /etc/fluent/config.d
          readOnly: true
      volumes:
      - name: shared-log
        emptyDir: {}
      - name: timezone
        hostPath:
          path: /etc/localtime
      - name: fluentd-config
        configMap:
          name: fluentd-es-configmap
      - name: fluentd-modules-config
        configMap:
          name: fluentd-modules-es-configmap
```

* Kibana中的记录效果  

![1531833877689](images/1531833877689.png)  

![1531834015895](images/1531834015895.png)  

#### 7.4.1.2 应用日志之全局监控  

下面示例每台k8s节点上仅部署一个独立的Fluentd Pod，这里可以通过多种方式实现日志采集及区分：  

* **方式一：** 将所有应用日志存储在主机的某个“目录”下，然后配置fluentd采集该“目录”下所有日志，此种方式仅能通过应用自身添加日志信息来解决区分问题，logback配置和Yaml配置与上面类似。  
* **方式二：** 通过配置采集运行中docker容器的前台输出日志文件的方式实现对应用日志的采集，对于日志的区分问题可以采用上面的方法解决，也可以通过一个插件在每条日志记录中添加k8s元数据来解决。下面示例如何通过插件解决区分问题：  

`fluentd-app-es-ds-all.yaml`

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fluentd
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  name: fluentd
rules:
- apiGroups:
  - ""
  resources:
  - pods
  - namespaces
  verbs:
  - get
  - list
  - watch
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: fluentd
roleRef:
  kind: ClusterRole
  name: fluentd
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: ServiceAccount
  name: fluentd
  namespace: default
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentd-es-ds-configmap
data:
  fluent.conf: |-
    # 配置导入指定路径指定规则名称的所有模块配置
    @include /etc/fluent/config.d/*.conf	
    # 配置不收集fluentd自己的日志，避免死循环
    <match fluent.**>
      @type null
    </match>

    # filter指令确定事件处理管道，下面示例使用插件添加kubernetes相关元数据，如所属Pod名称/容器名称等...
    <filter app.k8s.**>
      @type kubernetes_metadata
      @id filter_kube_metadata
    </filter>

    # match指令用于确定输出目标
    <match **>
      @type elasticsearch
      @id out_es
      log_level info
      include_tag_key true
      host "#{ENV['FLUENT_ELASTICSEARCH_HOST']}"
      port "#{ENV['FLUENT_ELASTICSEARCH_PORT']}"
      scheme "#{ENV['FLUENT_ELASTICSEARCH_SCHEME'] || 'http'}"
      ssl_verify "#{ENV['FLUENT_ELASTICSEARCH_SSL_VERIFY'] || 'true'}"
      user "#{ENV['FLUENT_ELASTICSEARCH_USER']}"
      password "#{ENV['FLUENT_ELASTICSEARCH_PASSWORD']}"
      reload_connections "#{ENV['FLUENT_ELASTICSEARCH_RELOAD_CONNECTIONS'] || 'true'}"
      logstash_prefix "#{ENV['FLUENT_ELASTICSEARCH_LOGSTASH_PREFIX'] || 'logstash'}"
      logstash_format true
      <buffer>
        flush_thread_count 8
        flush_interval 5s
        chunk_limit_size 2M
        queue_limit_length 32
        retry_max_interval 30
        retry_forever true
      </buffer>
    </match>
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentd-modules-es-ds-configmap
data:
  app.input.conf: |-
    # source指令用于确认输入源
    <source>
      # 该输入配置的唯一名称
      @id fluentd-container-app.log
      # 指定插件类型
      @type tail
      #format json
      # 读取的输入位置，这里使用通配符匹配应用容器Pod名，此路径/var/log/containers/下都是记录了运行容器前台打印日志的文件
      path /var/log/containers/*spring-boot-log-host*.log
      # (官方强烈推荐配置此项)fluentd会将上次读取的位置记录到此文件中
      pos_file /var/log/containers/fluentd-container-app.log.pos
      # 默认使用的是local time，这里配置解决ES中记录存储时间不正确问题
      utc true
      # 为该输入源添加标签，便于让match指令按一定规则确定输出源
      tag app.k8s.*
      # 开始从文件头部读取日志，而不是底部
      read_from_head true
      # 这里配置实现异常日志多行合并
      <parse>
        @type multiline
        format_firstline /^.*log":"\[/
        format1 /^(?<log>.*)/
      </parse>
    </source>
---
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: spring-boot-log-host
spec:
  replicas: 3
  template:
    metadata:
      labels:
        app-beat: spring-boot-log-host
    spec:
      terminationGracePeriodSeconds: 30
      containers:
      - name: spring-boot-fluentd
        image: 172.18.3.108/ebk/spring-boot-log-host:v1
        #imagePullPolicy: Always
        ports:
        - containerPort: 8666
        volumeMounts:
        - name: timezone
          mountPath: /etc/localtime
      volumes:
      - name: timezone
        hostPath:
          path: /etc/localtime
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluentd-container-app-logging
spec:
  selector:
    matchLabels:
      k8s-app: fluentd-container-app-logging
  template:
    metadata:
      labels:
        k8s-app: fluentd-container-app-logging
    spec:
      serviceAccountName: fluentd
      containers:
      - name: fluentd
        image: fluent/fluentd-kubernetes-daemonset:v1.2.2-debian-elasticsearch
        securityContext:
          runAsUser: 0
        env:
          - name: FLUENT_ELASTICSEARCH_HOST
            value: "elasticsearch"
          - name: FLUENT_ELASTICSEARCH_PORT
            value: "9200"
          - name: FLUENT_ELASTICSEARCH_SCHEME
            value: "http"
          - name: FLUENT_ELASTICSEARCH_SSL_VERIFY
            value: "true"
          - name: FLUENT_ELASTICSEARCH_USER
            value: "elastic"
          - name: FLUENT_ELASTICSEARCH_PASSWORD
            value: "changeme"
          - name: FLUENT_ELASTICSEARCH_RELOAD_CONNECTIONS
            value: "true"
          - name: FLUENT_ELASTICSEARCH_LOGSTASH_PREFIX
            value: "logstash"
        resources:
          limits:
            memory: 200Mi
          requests:
            cpu: 100m
            memory: 200Mi
        volumeMounts:
        - name: varlog
          mountPath: /var/log
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
        - name: timezone
          mountPath: /etc/localtime
        - name: fluentd-ds-config
          mountPath: /fluentd/etc/
          readOnly: true
        - name: fluentd-modules-ds-config
          mountPath: /etc/fluent/config.d
          readOnly: true
      terminationGracePeriodSeconds: 30
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
      - name: timezone
        hostPath:
          path: /etc/localtime
      - name: fluentd-ds-config
        configMap:
          name: fluentd-es-ds-configmap
      - name: fluentd-modules-ds-config
        configMap:
          name: fluentd-modules-es-ds-configmap
```

> **Note：** 要配置utc true，否则存储时日志时间会有问题，因差8个小时，导致在kibana中选择Last 15minutes查看不到日志，产生日志未采集到的错觉。  

Kibana中的记录效果  

![1531836123253](images/1531836123253.png)  

![1531836288014](images/1531836288014.png)  

从上图中可以看出通过采集app容器前台输出的方式，其日志数据展现结构不美观，后面还需要一些办法来优化。  

### 7.4.2 Filebeat日志监控    

#### 7.4.2.1 应用日志之局部监控   

下面示例在同一个Pod中部署app和filebeat，这里可以通过两种方式实现日志区分：一是通过app自身在记录日志时添加一些信息来实现区分；二是通过filebeat自带字段beat.hostname/beat.name/host.name来实现区分；三是添加`add_host_metadata`配置添加“主机”相关信息实现区分。  

`filebeat-app-dep-all.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: filebeat-configmap
data:
  filebeat.yml: |-
    # Filebeat prospectors
    filebeat.prospectors:
    - type: log
      enabled: true
      paths:
      - /logs/*.json
      # 将每条日志记录中的key提升到根节点下
      json.keys_under_root: true
      # 遇到无法解析的json串，添加一个error字段记录错误
      json.add_error_key: true

    processors:
    # 配置添加时区字段，~代表使用默认配置
    - add_locale: ~
    # 配置添加“主机”元数据
    - add_host_metadata: ~
 
    # Filebeat modules
    filebeat.config.modules:
      path: ${path.config}/modules.d/*.yml
      reload.enabled: false
      #reload.period: 10s

    # General
    tags: ["k8s-beat"]

    # Dashboards
    setup.dashboards.enabled: true

    # Kibana
    setup.kibana:
      host: ${KIBANA_HOST}:${KIBANA_PORT}
  
    # Outputs
    ## Elasticsearch output
    output.elasticsearch:
      hosts: ['${ELASTICSEARCH_HOST}:${ELASTICSEARCH_PORT}']
      username: ${ELASTICSEARCH_USERNAME}
      password: ${ELASTICSEARCH_PASSWORD}
---
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
      terminationGracePeriodSeconds: 30
      containers:
      - name: spring-boot-filebeat
        #image: 172.18.3.108/ebk/spring-boot-filebeat:v1
        image: 172.18.3.108/ebk/spring-boot-log-host:v1
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
        - name: config
          mountPath: /etc/filebeat.yml
          readOnly: true
          subPath: filebeat.yml
      volumes:
      - name: shared-log
        emptyDir: {}
      - name: timezone
        hostPath:
          path: /etc/localtime
      - name: config
        configMap:
          name: filebeat-configmap
```

Kibana中记录效果  

![1531839213622](images/1531839213622.png)  

![1531839328331](images/1531839328331.png)  

#### 7.4.2.2 应用日志之全局监控   

下面示例每台k8s节点上仅部署一个独立的Filebeat Pod，这里可以通过多种方式实现日志采集及区分：  

- **方式一：** 将所有应用日志存储在主机的某个“目录”下，然后配置Filebeat采集该“目录”下所有日志，此种方式仅能通过应用自身添加日志信息来解决区分问题，Yaml配置与上面类似。  
- **方式二：** 通过配置采集/var/log/containers路径下指定docker容器的前台输出日志文件的方式实现对应用日志的采集，此方式只能通过应用自身添加日志信息来解决区分问题：  

`filebeat-app-ds-all.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: filebeat-ds-configmap
data:
  filebeat.yml: |-
    # Filebeat prospectors
    filebeat.prospectors:
    - type: log
      enabled: true
      paths:
      #- /logs/*.json
      - /var/log/containers/*spring-boot*.log
      # 要添加这个配置，否则无法采集到日志
      symlinks: true

      ## Multiline options
      # 多行匹配规则设置
      multiline.pattern: ^\{"log":"\[
      # true表示会对匹配到的行进行合并
      multiline.negate: true
      # 设置合并到上一行的末尾还是开头
      multiline.match: after

    processors:
    - add_locale: ~
 
    # Filebeat modules
    filebeat.config.modules:
      path: ${path.config}/modules.d/*.yml
      reload.enabled: false
      #reload.period: 10s

    # General
    tags: ["k8s-beat"]

    # Dashboards
    setup.dashboards.enabled: true

    # Kibana
    setup.kibana:
      host: ${KIBANA_HOST}:${KIBANA_PORT}
  
    # Outputs
    ## Elasticsearch output
    output.elasticsearch:
      hosts: ['${ELASTICSEARCH_HOST}:${ELASTICSEARCH_PORT}']
      username: ${ELASTICSEARCH_USERNAME}
      password: ${ELASTICSEARCH_PASSWORD}
---
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
      terminationGracePeriodSeconds: 30
      containers:
      - name: spring-boot-filebeat
        image: 172.18.3.108/ebk/spring-boot-log-host:v1
        #imagePullPolicy: Always
        ports:
        - containerPort: 8666
        volumeMounts:
        - name: timezone
          mountPath: /etc/localtime
      volumes:
      - name: timezone
        hostPath:
          path: /etc/localtime
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: filebeat-app-container
  labels:
    app-beat: filebeat-app-container
spec:
  selector:
    matchLabels:
      app-beat: filebeat-app-container
  template:
    metadata:
      labels:
        app-beat: filebeat-app-container
    spec:
      terminationGracePeriodSeconds: 30
      containers:
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
        - name: timezone
          mountPath: /etc/localtime
        - name: config
          mountPath: /etc/filebeat.yml
          readOnly: true
          subPath: filebeat.yml
        - name: varlog
          mountPath: /var/log
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
      volumes:
      - name: timezone
        hostPath:
          path: /etc/localtime
      - name: config
        configMap:
          name: filebeat-ds-configmap
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
```

Kibana中记录效果  

![1531841174093](images/1531841174093.png)  

![1531841348610](images/1531841348610.png)  

* **方式三：**  通过配置采集/var/lib/docker/containers路径下所有docker容器的前台输出日志文件的方式实现对应用日志的采集，此方式可以通过应用自身添加日志信息，或者通过使用filebeat提供的`add_kubernetes_metadata`处理器添加k8s元数据来解决区分问题：  

`filebeat-app-ds-all-metadata.yaml`

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kube-filebeat
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  namespace: default
  name: kube-filebeat
rules:
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
  verbs: ["get","list","watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kube-filebeat
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kube-filebeat
subjects:
- kind: ServiceAccount
  name: kube-filebeat
  namespace: default
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: filebeat-ds-configmap
data:
  filebeat.yml: |-
    # Filebeat inputs
    filebeat.inputs:
    - type: docker
      containers:
        path: "/var/lib/docker/containers"
        ids:
        - "*"

      ## Multiline options
      # 多行匹配规则设置
      multiline.pattern: '^\[.* - [0-9]+\.[0-9]+\..*[0-9]+\]'
      # true表示会对匹配到的行进行合并
      multiline.negate: true
      # 设置合并到上一行的末尾还是开头
      multiline.match: after
   
    processors:
    - add_locale: ~
    - add_kubernetes_metadata: ~
 
    # Filebeat modules
    filebeat.config.modules:
      path: ${path.config}/modules.d/*.yml
      reload.enabled: false
      #reload.period: 10s

    # General
    tags: ["k8s-beat"]

    # Dashboards
    setup.dashboards.enabled: true

    # Kibana
    setup.kibana:
      host: ${KIBANA_HOST}:${KIBANA_PORT}
  
    # Outputs
    ## Elasticsearch output
    output.elasticsearch:
      hosts: ['${ELASTICSEARCH_HOST}:${ELASTICSEARCH_PORT}']
      username: ${ELASTICSEARCH_USERNAME}
      password: ${ELASTICSEARCH_PASSWORD}
---
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
      terminationGracePeriodSeconds: 30
      containers:
      - name: spring-boot-filebeat
        image: 172.18.3.108/ebk/spring-boot-log-host:v1
        #imagePullPolicy: Always
        ports:
        - containerPort: 8666
        volumeMounts:
        - name: timezone
          mountPath: /etc/localtime
      volumes:
      - name: timezone
        hostPath:
          path: /etc/localtime
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: filebeat-app-container
  labels:
    app-beat: filebeat-app-container
spec:
  selector:
    matchLabels:
      app-beat: filebeat-app-container
  template:
    metadata:
      labels:
        app-beat: filebeat-app-container
    spec:
      terminationGracePeriodSeconds: 30
      serviceAccountName: kube-filebeat
      containers:
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
        - name: timezone
          mountPath: /etc/localtime
        - name: config
          mountPath: /etc/filebeat.yml
          readOnly: true
          subPath: filebeat.yml
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
      volumes:
      - name: timezone
        hostPath:
          path: /etc/localtime
      - name: config
        configMap:
          name: filebeat-ds-configmap
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
```

Kibana中记录效果  

![1531988682352](images/1531988682352.png)  

![1531988844462](images/1531988844462.png)  

> **Note：** 上面这种方式三目前没办法控制只收集名称满足一定规则的APP容器前台输出日志，而方式二虽然能够进行规则控制，但其日志记录不便于查看，且不便于后续可能的查询解析，尤其对于异常日志，其每一行都包含了"{log:"，为了解决这个问题，可以修改应用日志前台输出格式为json，然后配置filebeat将日志中的key提取到根下，下面是具体解决方案示例：  

```xml
# 配置前台打印日志格式为json
<appender name="STDOUT" class="ch.qos.logback.core.ConsoleAppender">
    <encoder class="net.logstash.logback.encoder.LoggingEventCompositeJsonEncoder">
        <providers>
            <arguments/>
            <stackTrace/>
            <timestamp>
                <timeZone>UTC</timeZone>
            </timestamp>
            <!-- Assign logger fields to JSON object -->
            <pattern>
                <pattern>
                    {
                    "hostName": "${HOSTNAME}",
                    "hostIP": "%ip",
                    "severity": "%level",
                    "service": "${springAppName:-}",
                    "thread": "%thread",
                    "logger": "%logger",
                    "message": "%message"
                    }
                </pattern>
            </pattern>
        </providers>
    </encoder>
</appender>
```

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: filebeat-ds-configmap
data:
  filebeat.yml: |-
    # Filebeat prospectors
    filebeat.prospectors:
    - type: log
      enabled: true
      paths:
      - /var/log/containers/*spring-boot*.log
      json.keys_under_root: true
      json.add_error_key: true
      symlinks: true
   
    processors:
    #- drop_fields:
        #when:
          #has_fields: ['stream','time']
        #fields: ['stream','time']
    # 解决日志记录格式问题
    - decode_json_fields:
        fields: ["log"]
        process_array: false
        max_depth: 2
        target: ""
        overwrite_keys: false
    #- drop_fields:
        #fields: ["message"]
    - add_locale: ~
 
    # Filebeat modules
    filebeat.config.modules:
      path: ${path.config}/modules.d/*.yml
      reload.enabled: false
      #reload.period: 10s

    # General
    tags: ["k8s-beat"]

    # Dashboards
    setup.dashboards.enabled: true

    # Kibana
    setup.kibana:
      host: ${KIBANA_HOST}:${KIBANA_PORT}
  
    # Outputs
    ## Elasticsearch output
    output.elasticsearch:
      hosts: ['${ELASTICSEARCH_HOST}:${ELASTICSEARCH_PORT}']
      username: ${ELASTICSEARCH_USERNAME}
      password: ${ELASTICSEARCH_PASSWORD}
---
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
      terminationGracePeriodSeconds: 30
      containers:
      - name: spring-boot-filebeat
        image: 172.18.3.108/ebk/spring-boot-log-host-json:v1
        #imagePullPolicy: Always
        ports:
        - containerPort: 8666
        volumeMounts:
        - name: timezone
          mountPath: /etc/localtime
      volumes:
      - name: timezone
        hostPath:
          path: /etc/localtime
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: filebeat-app-container
  labels:
    app-beat: filebeat-app-container
spec:
  selector:
    matchLabels:
      app-beat: filebeat-app-container
  template:
    metadata:
      labels:
        app-beat: filebeat-app-container
    spec:
      terminationGracePeriodSeconds: 30
      containers:
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
        - name: timezone
          mountPath: /etc/localtime
        - name: config
          mountPath: /etc/filebeat.yml
          readOnly: true
          subPath: filebeat.yml
        - name: varlog
          mountPath: /var/log
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
      volumes:
      - name: timezone
        hostPath:
          path: /etc/localtime
      - name: config
        configMap:
          name: filebeat-ds-configmap
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
```

Kibana中记录效果  

![1531990841369](images/1531990841369.png)  

![1531990991518](images/1531990991518.png)  

### 7.4.3 简单区别对比  

| 区别项       | fluentd                                           | filebeat                           |
| ------------ | ------------------------------------------------- | ---------------------------------- |
| 开发语言     | C和Ruby                                           | Go                                 |
| 开源协议     | Apache License 2.0                                | Apache License 2.0                 |
| 性价比       | 网络上有文章说filebeat综合性能更好                | 网络上有文章说filebeat综合性能更好 |
| 高可用       | 自身支持                                          | 不支持                             |
| 功能项       | 支持过滤/解析/格式化/缓冲等功能，支持众多插件扩展 | 不支持插件扩展                     |
| 自定义镜像   | 较复杂，需要先安装ruby环境                        | 较容易                             |
| 输出源       | 支持多数据源输出                                  | ES/Logstash/Kafka/Redis/File等     |
| Kibana可视化 | 无预定义模板                                      | 带预定义日志模板                   |
| GitHub Star  | 6561                                              | 5834（beats）                      |

总的来说，fluentd支持众多插件，支持高可用配置，其功能更强大，同样这就带来了使用上的复杂，其更多对标的是Logstash；而filebeat虽然功能上支持的少，但完全满足对日志采集及区分的需求，其优势更多的是包含大量软件日志图表模板。所以建议优先考虑使用filebeat，如果对于高可用及K8S运行日志采集有需求，才去考虑使用fluentd。


