Kubernetes API Server 权限管理实践
=================================

# API Server权限控制方式介绍

API Server权限控制分为三种：Authentication（身份认证）、Authorization(授权)、AdmissionControl(准入控制)。

## 身份认证：

当客户端向Kubernetes非只读端口发起API请求时，Kubernetes通过三种方式来认证用户的合法性。kubernetes中，验证用户是否有权限操作api的方式有三种：证书认证，token认证，基本信息认证。

## 证书认证

设置apiserver的启动参数：--client_ca_file=SOMEFILE ，这个被引用的文件中包含的验证client的证书，如果被验证通过，那么这个验证记录中的主体对象将会作为请求的username。

## Token认证

设置apiserver的启动参数：--token_auth_file=SOMEFILE。 token file的格式包含三列：token，username，userid。当使用token作为验证方式时，在对apiserver的http请求中，增加 一个Header字段：Authorization ，将它的值设置为：Bearer SOMETOKEN。

## 基本信息认证

设置apiserver的启动参数：--basic_auth_file=SOMEFILE，如果更改了文件中的密码，只有重新启动apiserver使 其重新生效。其文件的基本格式包含三列：passwork，username，userid。当使用此作为认证方式时，在对apiserver的http 请求中，增加一个Header字段：Authorization，将它的值设置为： Basic BASE64ENCODEDUSER:PASSWORD。

## 授权：

在Kubernetes中，认证和授权是分开的，而且授权发生在认证完成之后，认证过程是检验发起API请求的用户是不是他所声称的那个人。而授权过程则 判断此用户是否有执行该API请求的权限，因此授权是以认证的结果作为基础的。Kubernetes授权模块应用于所有对APIServer的HTTP访 问请求（只读端口除外），访问只读端口不需要认证和授权过程。APIServer启动时默认将authorization_mode设置为 AlwaysAllow模式，即永远允许。

Kubernetes授权模块检查每个HTTP请求并提取请求上下文中的所需属性（例如：user，resource kind，namespace）与访问控制规则进行比较。任何一个API请求在被处理前都需要通过一个或多个访问控制规则的验证。

目前Kubernetes支持并实现了以下的授权模式（authorization_mode），这些授权模式可以通过在apiserver启动时传入参数进行选择。
```
--authorization_mode=AlwaysDeny
--authorization_mode=AlwaysAllow
--authorization_mode=ABAC
```
AlwaysDeny 模式屏蔽所有的请求（一般用于测试）。AlwaysAllow模式允许所有请求，默认apiserver启动时采用的便是AlwaysAllow模式）。 ABAC（Attribute-Based Access Control，即基于属性的访问控制）模式则允许用户自定义授权访问控制规则。

## ABAC模式：

一个API请求中有4个属性被用于用户授权过程：

* UserName：String类型，用于标识发起请求的用户。如果不进行认证、授权操作，则该字符串为空。

* ReadOnly：bool类型，标识该请求是否仅进行只读操作（GET就是只读操作）。

* Kind：String类型，用于标识要访问的Kubernetes资源对象的类型。当访问例如/api/v1beta1/pods等API endpoint时，Kind属性才非空，但访问其他endpoint时，例如/version，/healthz等，Kind属性为空。

* Namespace：String类型，用于标识要访问的Kubernetes资源对象所在的namespace。

对ABAC模式，在apiserver启动时除了需要传入--authorization_mode=ABAC选项外，还需要指定 --authorization_policy_file=SOME_FILENAME。authorization_policy_file文件的每一 行都是一个JSON对象，该JSON对象是一个没有嵌套的map数据结构，代表一个访问控制规则对象。一个访问控制规则对象是一个有以下字段的map：

* user：--token_auth_file指定的user字符串。

* readonly：true或false，如果是true则表明该规则只应用于GET请求。

* kind：Kubernetes内置资源对象类型，例如pods、events等。

* namespace：也可以缩写成ns。

一个简单的访问控制规则文件如下所示，每一行定义一条规则。
```
{"user":"admin"}

{"user":"alice", "ns": "projectCaribou"}

{"user":"kubelet", "readonly": true, "kind": "pods"}

{"user":"kubelet", "kind": "events"}

{"user":"bob", "kind": "pods", "readonly": true, "ns": "projectCaribou"}
```
注：缺省的字段与该字段类型的零值（空字符串，0，false等）等价。

规则逐行说明如下。

* 第一行表明，admin可以做任何事情，不受namespace，资源类型，请求类型的限制。

* 第二行表明，alice能够在namespace "projectCaribou"中做任何事情，不受资源类型，请求类型的限制。

* 第三行表明，kubelet有权限读任何一个pod的信息。

* 第四行表明，kubelet有权限读写任何一个event。

* 第五行表明，Bob有权限读取在namespace "projectCaribou"中所有pod的信息。

一个授权过程就是一个比较API请求中各属性与访问控制规则文件中对应的各字段是否匹配的一个过程。当apiserver接收到一个API请求时，该请求 的各属性就已经确定了，如果有一个属性未被设置，则apiserver将其设为该类型的空值（空字符串，0，false等）。匹配规则很简单，如下所示。

* 如果API请求中的某个属性为空值，则规定该属性与访问控制规则文件中对应的字段匹配。

* 如果访问控制规则的某个字段为空值，则规定该字段与API请求的对应属性匹配。

* 如果API请求中的属性值非空且访问控制规则的某个字段值也非空，则将这两个值进行比较，如果相同则匹配，反之则不匹配。

* API请求的属性元组（tuple）会与访问控制规则文件中的所有规则逐条匹配，只要有一条匹配则表示匹配成功，如若不然，则授权失败。

## 准入控制：

准入控制admission controller本质上为一段准入代码，在对kubernetes api的请求过程中，顺序为 先经过 认证 & 授权，然后执行准入操作，再对目标对象进行操作。这个准入代码在apiserver中，而且必须被编译到二进制文件中才能被执行。

在对集群进行请求时，每个准入控制代码都按照一定顺序执行。如果有一个准入控制拒绝了此次请求，那么整个请求的结果将会立即返回，并提示用户相应的error信息。

在某些情况下，为了适用于应用系统的配置，准入逻辑可能会改变目标对象。此外，准入逻辑也会改变请求操作的一部分相关资源。

* 作用

在kubernetes中，一些高级特性正常运行的前提条件为，将一些准入模块处于enable状态。总结下，对于kubernetes apiserver，如果不适当的配置准入控制模块，它就不能称作是一个完整的server，某些功能也不会正常的生效。

* 开启方式

在kubernetes apiserver中有一个参数：admission_control，他的值为一串用逗号连接的 有序的 准入模块列表，设置后，就可在对象被操作前执行一定顺序的准入模块调用。

* 模块功能

    - AlwaysAdmit：允许所有请求

    - AlwaysDeny：禁止所有请求，多用于测试环境。

    - DenyExecOnPrivileged：它会拦截所有想在privileged container上执行命令的请求。如果自己的集群支持privileged container，自己又希望限制用户在这些privileged container上执行命令，那么强烈推荐使用它。

    - ServiceAccount：这个plug-in将 serviceAccounts实现了自动化，如果想要使用ServiceAccount 对象，那么强烈推荐使用它。

    关于serviceAccount的描述如下： 一个serviceAccount为运行在pod内的进程添加了相应的认证信息。当准入模块中开启了此插件（默认开启），那么当pod创建或修改时他会做一下事情：

    1. 如果pod没有serviceAccount属性，将这个pod的serviceAccount属性设为“default”；

    1. 确保pod使用de serviceAccount始终存在；

    1. 如果LimitSecretReferences 设置为true，当这个pod引用了Secret对象却没引用ServiceAccount对象，弃置这个pod；

    1. 如果这个pod没有包含任何ImagePullSecrets，则serviceAccount的ImagePullSecrets被添加给这个pod；

    1. 如果MountServiceAccountToken为true，则将pod中的container添加一个VolumeMount 。

    - SecurityContextDeny：这个插件将会将使用了 SecurityContext的pod中定义的选项全部失效。SecurityContext 在container中定义了操作系统级别的安全设定（uid, gid, capabilities, SELinux等等）。

    - ResourceQuota：它会观察所有的请求，确保在namespace中ResourceQuota对象处列举的container没有任何异常。 如果在kubernetes中使用了ResourceQuota对象，就必须使用这个插件来约束container。推荐在admission control参数列表中，这个插件排最后一个。

    - LimitRanger：他会观察所有的请求，确保没有违反已经定义好的约束条件，这些条件定义在namespace中LimitRange对象中。如果在kubernetes中使用LimitRange对象，则必须使用这个插件。

    - NamespaceExists：它会观察所有的请求，如果请求尝试创建一个不存在的namespace，则这个请求被拒绝。

## 推荐插件顺序
```
--admission_control=NamespaceLifecycle,NamespaceExists,LimitRanger,SecurityContextDeny,ServiceAccount, ResourceQuota
```

## 验证流程

1.  API Server的初始化参数中设置了一些与权限认证相关的默认属性：

    - 安全监听端口：    SecurePort:               8443 读/写 权限，支持x509安全证书和x509私钥认证

    - 非安全监听端口：InsecurePort:             8080 没有用户身份认证和授权，有读/写 权限

    - 授权模式：           AuthorizationMode:   "AlwaysAllow",

    - 准入控制插件：    AdmissionControl:     "AlwaysAdmit"

2. API Server启动时可以设置与权限认证相关的参数：

    - --insecure_port                               自定义非安全监听端口

    - --secure_port                                  自定义安全监听端口

    - --tls_cert_file                                   设置安全证书文件

    - --tls_private_key_file                      设置私钥文件

    - --cert_dir                                         安全证书文件和私钥文件被设置时，此属性忽略。安全证书文件和私钥文件未设置时，apiserver会自动为该端口绑定的公有IP地址分别生成一个自注册的证书文件和密钥并将它们存储在/var/run/kubernetes下

    - --service_account_key_file             服务账号文件，包含x509 公私钥

    - --client_ca_file                                 client证书文件

    - --token_auth_file                             token文件

    - --basic_auth_file                             基本信息认证文件

    - --authorization_mode                     授权模式

    - --ahtuorization_policy_file              授权文件

    - --admission_control                       准入控制模块列表

    - --admission_control_config_file     准入控制配置文件

3. 解析入参，进行认证信息提取：

    - 公私钥文件设置：查看ServerAccountKeyFile是否已指定，如果未指定，并且TLSPrivateKeyFile被指定，则判断 TLSPrivateKeyFile中是否包含有效的RSA key，包含时，将TLSPrivateKeyFile作为ServerAccountKeyFile。

    - 身份认证信息提取：从参 数设置的CSV文件中取出username，userID，password（或者token）封装成map结构，key为username,value 为三种属性的struct。从basicAuthFile, clientCAFile, tokenFile, serviceAccountKeyFile（serviceAccountLookup） 中取user信息,得到一个验证信息的map数组。

    - 授权信息提取：读取设置的授权文件，解析字符串，返回授权信息数组。（包含 username,group,resource,read only,namespace）Make the "cluster" Kinds be one API group (minions, bindings，events,endpoints)。The "user" Kinds are another (pods,services,replicationControllers,operations)。

    - 准入控制插件：获取所有插件名，返回准入控制接口（执行所有插件）

4. 将身份认证信息、授权信息、准入控制插件作为Master的配置，New Master。

5. 请求认证：

    - 调apiserver的NewRequestAttributeGetter方法，从请求中提取授权信息，调用WithAuthorizationCheck方法（授权验证）。

    - 调 用handler的NewRequestAuthenticator方法，Request中提取authencate信息,调用 AuthenticateRequest方法（对client certificates，token,basic auth分别有不同的验证方法）。


## 补充

## 身份认证：

token认证，请求时，在请求头中加入 Authorization:bearer token字符串。CSV文件中，三列分别为 token,username,userid。当CSV中有与请求的Authorization匹配行时，认证成功。

basic auth认证，请求时，在请求头中加入 Authorization:basic base64编码的user:password字符串。CSV文件中，三列分别为 password,username,userid。当CSV文件中有与请求的Ahtuorization匹配行时，认证成功。

## 证书校验：

API Server启动时，指定服务端数字证书和密钥（如果不指定，会在server启动时自动生成），指定客户端ca文件，server启动时，会解析ca文 件，遍历其中的cert，加入certpool。在Server的TLSConfig中指定认证模式：目前使用的是 RequestClientCert（不强制认证，无认证时不拒绝连接，允许其他认证），此外还有其他认证模式 requireAndVerifyClientCert(强制校验)。使用ListenAndServeTLS（将服务端数字证书和密钥作为参数）监听在 安全端口。

 

## API Server权限控制操作（暂时未加入namespace）测试：

启动server：指定token验证文件、授权方式、授权文件
```
./_output/local/bin/linux/amd64/canary-apiserver --logtostderr=true --log-dir=/tmp --v=4 --etcd_servers=http://127.0.0.1:4001 --insecure_bind_address=127.0.0.1 --insecure_port=8088 --secure_port=8442 --kubelet_port=10250 --service-cluster-ip-range=10.1.1.0/24 --allow_privileged=true --runtime-config="api/v1beta3=false" --redis-addr=localhost:6379 --profiling=true --token_auth_file=token.csv --authorization_mode=ABAC --authorization_policy_file=abac.csv
```
Token文件内容：
```
abcdef,hankai,123456

abcdefg,hk,123457

abcd,admin,1234

abc,hhh,111
```
 

授权文件内容：
```
{“user”:”admin”}

{“user”:”hankai”,”readonly”:true}

{“user”:”hhh”,”resource”:”apps”}

{“user”:”hk”,”readonly”:true,”resource”:”namespaces”}
```


验证：admin（有读写所有resource的权限）
```
curl -X GET -H "Content-Type: application/json" -H "Authorization: bearer abcd" -k https://10.57.104.59:8442/api/v1/apps               

curl -X GET -H "Content-Type: application/json" -H "Authorization: bearer abcd" -k https://10.57.104.59:8442/api/v1/namespaces       

curl -X POST -H "Content-Type: application/json" -H "Authorization: bearer abcd" -d@'n1.json' -k https://10.57.104.59:8442/api/v1/namespaces     

curl -X POST -H "Content-Type: application/json" -H "Authorization: bearer abcd" -d@'app_demo1.json' -k https://10.57.104.59:8442/api/v1/apps
```
验证 hankai (只有读权限GET)
```
curl -X POST -H "Content-Type: application/json" -H "Authorization: bearer abcdef" -d@'app_demo1.json' -k https://10.57.104.59:8442/api/v1/apps               forbidden

curl -X POST -H "Content-Type: application/json" -H "Authorization: bearer abcdef" -d@'n1.json' -k https://10.57.104.59:8442/api/v1/namespaces                                    forbidden

curl -X GET -H "Content-Type: application/json" -H "Authorization: bearer abcdef"  -k https://10.57.104.59:8442/api/v1/namespaces

curl -X GET -H "Content-Type: application/json" -H "Authorization: bearer abcdef"  -k https://10.57.104.59:8442/api/v1/apps
```
验证 hk (只有对namespaces的GET权)
```
curl -X GET -H "Content-Type: application/json" -H "Authorization: bearer abcdefg"  -k https://10.57.104.59:8442/api/v1/apps                   forbidden 

curl -X GET -H "Content-Type: application/json" -H "Authorization: bearer abcdefg"  -k https://10.57.104.59:8442/api/v1/namespaces

curl -X POST -H "Content-Type: application/json" -H "Authorization: bearer abcdefg" -d@'n1.json' -k https://10.57.104.59:8442/api/v1/namespaces                            forbidden

curl -X POST -H "Content-Type: application/json" -H "Authorization: bearer abcdefg" -d@'app_demo1.json' -k https://10.57.104.59:8442/api/v1/apps                                    forbidden
```
验证hhh（拥有对apps的读写权）
```
curl -X POST -H "Content-Type: application/json" -H "Authorization: bearer abc" -d@'app_demo1.json' -k https://10.57.104.59:8442/api/v1/apps

curl -X GET -H "Content-Type: application/json" -H "Authorization: bearer abc"  -k https://10.57.104.59:8442/api/v1/apps

curl -X GET -H "Content-Type: application/json" -H "Authorization: bearer abc"  -k https://10.57.104.59:8442/api/v1/namespaces                         forbidden

curl -X POST -H "Content-Type: application/json" -H "Authorization: bearer abc" -d@'n1.json' -k https://10.57.104.59:8442/api/v1/namespaces                            forbidden
```
注：后续只需要在abac.csv文件的每列中，指定namespace，就可以实现user对指定namespace的操作权限。

## 新增：TSL 客户端证书认证

使用自生成证书测试：使用openssl生成server.crt,server.key,ca.key,ca.crt。Server启动时，传入 --tls_cert_file=server.crt --tls_private_key_file=server.key --client_ca_file=ca.crt
```
./_output/local/bin/linux/amd64/canary-apiserver --logtostderr=true --log-dir=/tmp --v=4 --etcd_servers=http://127.0.0.1:4001 --insecure_bind_address=7.0.0.1 --insecure_port=8088 --secure_port=8442 --kubelet_port=10250 --service-cluster-ip-range=10.1.1.0/24 --allow_privileged=true --runtime-config="api/v1beta3=false" --redis-addr=localhost:6379 --profiling=true --tls_cert_file=server.crt --tls_private_key_file=server.key --client_ca_file=ca.crt  --token_auth_file=token.csv --authorization_mode=ABAC --authorization_policy_file=abac.csv
```
请求时，通过-cacert 指定客户端证书 （可以通过修改opnessl的配置文件指定客户端证书的路径，或者浏览器中导入客户端证书） curl -X GET --cacert ca.crt -H "Content-Type: application/json" -H "Authorization: bearer abcd" -k https://10.57.104.59:8442/api/v1/apps 即可实现认证。