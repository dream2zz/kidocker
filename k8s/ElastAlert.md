## 7.5 ElastAlert报警框架预研  

### 7.5.1 技术简介  

ElastAlert 是 Yelp 公司开发的一款基于 Elasticsearch 的报警框架，开发语言基于Python，支持 Elasticsearch 的各个版本。程序的主要功能是从 Elasticsearch 当中查询出匹配规则类型的数据进行报警。

ElastAlert 支持的报警类型（规则）主要包括：

- 匹配当 Y 时间段内有 X 个事件（ frequency 类型 ）
- 匹配事件发生率上升或者下降 （ spike 类型 ）
- 匹配当 Y 时间段内少于 X 个事件（ flatline 类型 ）
- 匹配当某个值符合白名单或者黑名单时（ blacklist 和 whitelist 类型 ）
- 匹配任何符合过滤器的事件（ any 类型 ）
- 匹配当一段时间内某字段有两个不同的值（ change 类型 ）

目前，内置支持以下报警渠道：

`Command ` `Email` `JIRA` `OpsGenie` `SNS` `HipChat` `Stride` `MS Teams` `Slack` `Telegram` `PagerDuty` `Exotel` `Twilio` `VictorOps` `Gitter` `ServiceNow` `Debug` `Stomp` `Alerta` `HTTP POST`  

除了这种基本用法之外，还有许多其他功能使得ElastAlert更强大：

- 警报链接到 Kibana 的 dashboards 上
- 任意字段的汇总数据
- 将警报结合到定期报告当中
- 使用唯一键值分隔报警
- 拦截并增强匹配到的数据  

ElastAlert 有很多特性来保证可用性，尤其是当 Elasticsearch 不可靠或者重启时候：  

- ElastAlert 将其状态存储在Elasticsearch 当中，并会在启动时候恢复停止前的状态。
- 当 Elasticsearch 不可达，ElastAlert 会等到其恢复再运行。
- 当警报发生错误时，会自动重试一段时间。

### 7.5.2 配置示例  

#### 7.5.2.1 Email报警    

下面示例监控应用日志，如果在1分钟内出现2次异常会进行Email报警。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: elastalert-configmap
data:
  elastalert_config.yaml: |-
    # 定义规则目录
    rules_folder: /opt/rules
    scan_subdirectories: false
    # 定义查询ES时间间隔，秒~周
    run_every:
      minutes: 1
    # 缓存最近结果的时间周期
    buffer_time:
      minutes: 15
    # ES相关信息
    es_host: ${ES_HOST}
    es_port: ${ES_PORT}
    es_username: ${ES_USERNAME}
    es_password: ${ES_PASSWORD}
    # 定义ES中用来存储elastalert元数据的索引
    writeback_index: elastalert_status
    # 如果发送警报失败，其会在下面这段时间内重试
    alert_time_limit:
      days: 2
  smtp_auth_file.yaml: |-
    # 身份验证相关配置，***替换为真实邮箱配置
    user: *****@163.com
    # POP3密码
    password: ******
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: elastalert-rules-configmap
data:
  email_frequency.yaml: |-
    # 可选
    #es_host: ${ES_HOST}
    #es_port: ${ES_PORT}
    #es_username: ${ES_USERNAME}
    #es_password: ${ES_PASSWORD}

    # 唯一的规则名
    name: Test frequency rule
    # 规则类型，frequency对应num_events
    type: frequency
    # 监控的es数据索引
    index: filebeat-*
    # 当设置的报警规则触发2次后执行报警
    num_events: 2
    # num_events必须在这段时间内触发报警
    timeframe:
      # 触发报警有效期为1分钟内，可以定义hours等
      minutes: 1
    # 配置过滤器，ES的query-dsl语法，下面意思当查到severity字段为ERROR时，会按上面规则进行过滤
    filter:
    - query:
        query_string:
          query: "severity: ERROR"
    
    # 5分钟内，当某个字段不同时，会被当作不同的报警处理
    #query_key:
      #- beat.name
    realert:
      minutes: 5

    # 当发生匹配时报警类型
    alert:
    - "email"

    # 接收报警的邮箱地址列表
    email:
    - "***@163.com"

    # 发送邮箱相关设置
    smtp_host: "smtp.163.com"
    smtp_port: 25
    smtp_auth_file: "/opt/config/smtp_auth_file.yaml"
    # 添加reply to头信息
    email_reply_to: "***@163.com"
    # 添加From头信息
    from_addr: "***@163.com"
    # 添加抄送给自己，否则会报554错误（垃圾邮件）
    cc: "***@163.com"
---
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: elastalert
  labels:
    k8s-app: elastalert
spec:
  replicas: 1
  template:
    metadata:
      labels:
        k8s-app: elastalert
    spec:
      containers:
      - name: elastalert
        # 这里借用了rancher应用商店内helm配置的镜像
        image: jertel/elastalert-docker
        #imagePullPolicy: Always
        env:
        # 环境变量名必须是下面的名称，否则elastalert无法启动
        - name: ES_HOST
          value: elasticsearch
        - name: ES_PORT
          value: "9200"
        - name: ES_USERNAME
          value: elastic
        - name: ES_PASSWORD
          value: changeme
        volumeMounts:
        - name: config
          mountPath: /opt/config
        - name: rules
          mountPath: /opt/rules
      volumes:
      - name: config
        configMap:
          name: elastalert-configmap
      - name: rules
        configMap:
          name: elastalert-rules-configmap
```

#### 7.5.2.2 Http Post报警  

下面示例监控应用日志，如果在1分钟内出现2次异常会通过HTTP POST的方式将报警信息发送到指定接口进行处理。  

```java
@RestController
@RequestMapping("/api/v1")
public class ElastAlertController {
    private static final Logger log = LoggerFactory.getLogger(ElastAlertController.class);

    @PostMapping("/elastalert/json")
    public ResponseEntity<String> handlerJsonAlert(@RequestBody String jsonStr) {
//        System.out.println(jsonStr);
        // 这里简单的把接收到的报警信息记录日志，然后我们可以在kibana中查看到该信息。
        log.info(jsonStr);
        return ResponseEntity.status(HttpStatus.CREATED).body(jsonStr);
    }
}
```

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: elastalert-configmap
data:
  elastalert_config.yaml: |-
    # 定义规则目录
    rules_folder: /opt/rules
    scan_subdirectories: false
    # 定义查询ES时间间隔，秒~周
    run_every:
      minutes: 1
    # 缓存最近结果的时间周期
    buffer_time:
      minutes: 15
    # ES相关信息
    es_host: ${ES_HOST}
    es_port: ${ES_PORT}
    es_username: ${ES_USERNAME}
    es_password: ${ES_PASSWORD}
    # 定义用来ES中用来存储elastalert元数据的索引
    writeback_index: elastalert_status
    # 如果发送警报失败，其会在下面这段时间内重试
    alert_time_limit:
      days: 2
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: elastalert-rules-configmap
data:
  email_frequency.yaml: |-
    # 可选
    #es_host: ${ES_HOST}
    #es_port: ${ES_PORT}
    #es_username: ${ES_USERNAME}
    #es_password: ${ES_PASSWORD}

    # 唯一的规则名
    name: Test frequency rule
    # 规则类型，frequency对应num_events
    type: frequency
    # 监控的es数据索引
    index: filebeat-*
    # 当设置的报警规则触发2次后执行报警
    num_events: 2
    # num_events必须在这段时间内触发报警
    timeframe:
      # 触发报警有效期为1分钟内，可以定义hours等
      minutes: 1
    # 配置过滤器，ES的query-dsl语法
    filter:
    - query:
        query_string:
          query: "severity: ERROR"
    
    # 5分钟内，当某字段不同时，会被当作不同的报警处理
    #query_key:
      #- beat.name
    realert:
      minutes: 5

    # 当发生匹配时报警类型
    alert:
    - post

    # 相关设置
    ## 处理报警信息的接口，spring-boot-filebeat-alert为自定义处理服务在k8s中部署的service名
    http_post_url: "http://spring-boot-filebeat-alert:8666/api/v1/elastalert/json"
    ## 可以给报警信息添加自定义字段，这里示意添加了一个tag字段，还可以通过其它配置指定报警信息要发送哪些字段，也可对这些字段进行重命名。
    http_post_static_payload:
      tag: just test http alert
---
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: elastalert
  labels:
    k8s-app: elastalert
spec:
  replicas: 1
  template:
    metadata:
      labels:
        k8s-app: elastalert
    spec:
      containers:
      - name: elastalert
        image: jertel/elastalert-docker
        #imagePullPolicy: Always
        env:
        - name: ES_HOST
          value: elasticsearch
        - name: ES_PORT
          value: "9200"
        - name: ES_USERNAME
          value: elastic
        - name: ES_PASSWORD
          value: changeme
        volumeMounts:
        - name: config
          mountPath: /opt/config
        - name: rules
          mountPath: /opt/rules
      volumes:
      - name: config
        configMap:
          name: elastalert-configmap
      - name: rules
        configMap:
          name: elastalert-rules-configmap
```

![1532592476305](images/1532592476305.png)  

### 7.5.3 Kibana插件   

#### 7.5.3.1 相关安装项    

* 构建安装了第三方elastalert-kibana插件的镜像

```dockerfile
# 基于官方kibana镜像构建安装elastalert-kibana插件，截止目前，最新仅提供6.2.4版本的elastalert-kibana插件
FROM docker.elastic.co/kibana/kibana-oss:6.2.4
# 执行安装插件命令
RUN /usr/share/kibana/bin/kibana-plugin install 'https://git.bitsensor.io/front-end/elastalert-kibana-plugin/builds/artifacts/6.2.4/raw/artifact/elastalert-kibana-plugin-latest.zip?job=build'

#EXPOSE 5601
#CMD ["/usr/local/bin/kibana-docker"]
```

* 安装部署第三方elastalert-server服务，用来提供REST API给elastalert-kibana插件调用  

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: elastalert-server-configmap
data:
  elastalert.yaml: |-
    # 定义规则目录
    rules_folder: /opt/elastalert/rules
    scan_subdirectories: false
    # 定义查询ES时间间隔，秒~周
    run_every:
      minutes: 1
    # 缓存最近结果的时间周期
    buffer_time:
      minutes: 15
    # ES相关信息
    es_host: ${ES_HOST}
    es_port: ${ES_PORT}
    es_username: ${ES_USERNAME}
    es_password: ${ES_PASSWORD}
    # 定义用来ES中用来存储elastalert元数据的索引
    writeback_index: elastalert_status
    # 如果发送警报失败，其会在下面这段时间内重试
    alert_time_limit:
      days: 2
---
apiVersion: v1
kind: Service
metadata:
  name: elastalert-server
  labels:
    k8s-app: elastalert-server
spec:
  selector:
    k8s-app: elastalert-server
  ports:
    # elastalert-server默认暴露3030端口
    - port: 3030
---
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: elastalert-server
  labels:
    k8s-app: elastalert-server
spec:
  replicas: 1
  template:
    metadata:
      labels:
        k8s-app: elastalert-server
    spec:
      containers:
      - name: elastalert-server
        # 第三方elastalert-server镜像
        image: bitsensor/elastalert
        #imagePullPolicy: Always
        ports:
        - containerPort: 3030
        env:
        - name: ES_HOST
          value: elasticsearch
        - name: ES_PORT
          value: "9200"
        - name: ES_USERNAME
          value: elastic
        - name: ES_PASSWORD
          value: changeme
        volumeMounts:
        - name: config
          mountPath: /opt/elastalert/config.yaml
          subPath: config.yaml
        - name: rules
          mountPath: /opt/elastalert/rules
      volumes:
      # 需要挂载一个空目录，否则容器启动会报错，且不能通过configmap挂载rules，否则也会报错
      - name: rules
        emptyDir: {}
      - name: config
        configMap:
          name: elastalert-server-configmap
          items:
          - key: elastalert.yaml
            path: config.yaml
```

* 部署安装了elastalert-kibana插件的Kibana应用  

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: kibana-alert-configmap
data:
  kibana.yml: |-
    server.name: kibana-alert
    server.host: "0"
    elasticsearch.url: http://elasticsearch:9200
    # 配置elastalert-server的访问地址
    elastalert.serverHost: elastalert-server
---
apiVersion: v1
kind: Service
metadata:
  name: kibana-alert
  labels:
    component: kibana-alert
spec:
  selector:
    component: kibana-alert
  type: NodePort
  ports:
    - name: http
      port: 5601
      nodePort: 30057
---
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: kibana-alert
  labels:
    component: kibana-alert
spec:
  replicas: 1
  selector:
    matchLabels:
      component: kibana-alert
  template:
    metadata:
      labels:
        component: kibana-alert
    spec:
      containers:
      - name: kibana-alert
        #image: docker.elastic.co/kibana/kibana-oss:6.3.0
        image: 172.18.3.108/ebk/kibana-alert:v1
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
        volumeMounts:
        - name: config
          mountPath: /usr/share/kibana/config/kibana.yml
          subPath: kibana.yml
      volumes:
      - name: config
        configMap:
          name: kibana-alert-configmap
```

经过上面的部署安装后，我们可以访问 http://hostip:30057 进入Kibana首页，下面是使用界面介绍：  

![1532593856033](images/1532593856033.png)  

![1532594142044](images/1532594142044.png)  

#### 7.5.3.2 使用示意图  

![kibana-elastalert-plugin-showcase](images/kibana-elastalert-plugin-showcase.gif)  

#### 7.5.3.3 版权说明  

以下部分内容翻译自ElastAlert Server官方License文件：  

版权所有©2018，BitSensor BV

如果满足以下条件，则允许以源代码和二进制形式重新分发和使用，无论是否经过修改：

* 源代码的重新分发必须保留上述版权声明、此条件列表和以下免责声明。
* 二进制形式的再分发必须在随分发提供的文档和其它材料中复制上述版权声明、此条件列表和以下免责声明。
* 未经事先书面许可，BitSensor ，BitSensor BV的名称及其贡献者的名称均不得用于支持或宣传从该软件派生的产品。但是，当明确说明使用ElastAlert Server插件（可以将其改为报警插件）时，可以使用这些名称。

本软件的一些免责声明...这里省略了。。。


