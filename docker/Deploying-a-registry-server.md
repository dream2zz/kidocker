Deploying a registry server
===========================

当公司开始使用docker，到官方的docker hub上下载（pull）镜像，显然很不切合实际，而且咱这公司的网络环境是私有环境，都不允许访问外网，那就更不可能到官方的hub去下载镜像。所以我们接下来分享实战构建企业级的**Docker Registry Server**。

然后我们来理解一下什么是docker镜像，什么是dockerregistry。理解docker镜像和docker registry的关系也非常容易。我们把docker镜像看成是“源代码文件“，registry server就是”git仓库“，平日我们写好的代码文件都需要push到代码仓库中，对于docker镜像也一样，镜像打包好以后需要提交到registry server服务器上让测试人员构建测试环境，或者是上线业务。

公司业务不仅仅是单个，而且还会越来越多，那么镜像也就相对会越来越多，我们需要重点考虑如何管理镜像之间的依赖关系，并要实现自动构建，实现持续集成。

镜像仓库好比就是APP store，我们可以到仓库里面去挑选自己想要的APP，然后下载到手机或者电脑上进行安装使用。docker镜像和仓库也类似。

目前docker registry版本是2.4，也是当前最新的版本。

registry2.4的特性有，目前是用go语言去写的，性能提升比v1能高2-3倍，安全和性能上有很多的提升，那么v1有哪些安全隐患呢？

v1版本，镜像的id是随机生成的，所以每次构建一个层都会随机生成一个新ID，即使是层的内容相同。这样会有一个风险就是层的内容文件会被串改，因为最终验证的是id，而不是里面的内容。

v2版本，镜像ID是通过sha256做hash得出来的，这样一来同样的内容就会得到的是一样的ID。镜像id这点能保证了，但还是有其他的问题。细心的同学会发现运行docker pull镜像下载完后，会看到Digest字段，看起来docker像是想用此字符来取代tag.只是猜测不知道后续会发展成什么一样。

这篇文章主要实战构建docker registry。

# 一、创建registry server端
安装server端，我们采用alpine操作系统，该系统需要能直接访问互联网。在安装好docker之后，进行下面的操作。

## 1.下载registry2.4镜像
```
docker pull registry:2.4
```
## 2.生成自签名证书
假设域名是：`c.io`
```
mkdir -p /home/u01/certs && cd /home/u01/certs
openssl req -x509 -days 3650 -subj '/CN=*/' -nodes -newkey rsa:2048 -keyout registry.key -out registry.crt
```
## 3.生成用户和密码
假设用户：admin 密码：p@ssw0rd，这里的账户名不能少于5位字符。
```
mkdir -p /home/u01/auth
sudo docker run --entrypoint htpasswd registry:2.4 -Bbn admin p@ssw0rd > /home/u01/auth/htpasswd
```
## 4.启动registry server
```
mkdir -p /home/u01/datas
```
```
sudo docker run -d -p 5000:5000 --restart=always --name registry \
-v /home/u01/auth:/auth \
-v /home/u01/certs:/certs \
-v /home/u01/datas:/var/lib/registry \
-e "REGISTRY_AUTH=htpasswd" \
-e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
-e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
-e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/registry.crt \
-e REGISTRY_HTTP_TLS_KEY=/certs/registry.key \
-e STANDALONE=false \
-e MIRROR_SOURCE=https://registry-1.docker.io \
-e MIRROR_SOURCE_INDEX=https://index.docker.io \
registry:2.4
```
确认registry server是UP状态，`docker ps -a | grep registry`

# 二、配置docker client端

## 1.创建证书目录(没有此目录，需要自己创建，注意端口号)
```
sudo mkdir -p /etc/docker/certs.d/172.18.26.2:5000
```
## 2.下载证书
```
wget http://172.18.3.103/Hakugei/Home/raw/master/certs/registry.crt
sudo mv registry.crt /etc/docker/certs.d/172.18.26.2:5000/ca.crt
```
## 3.域名解析
```
sudo -i
echo 172.18.24.104 c.io >> /etc/hosts
```
## 4.修改Docker配置
在Docker配置文件/etc/default/docker添加如下内容：
```
DOCKER_OPTS="--registry-mirror=http://c.io:5000"
```
重启Docker服务
```
systemctl daemon-reload
systemctl restart docker
```

## 三、验证测试

## 1.在server端下载镜像并更改tag
```
sudo docker pull alpine && sudo docker tag alpine c.io:5000/alpine
```
## 2.在server端登录
```
sudo docker login c.io:5000
```
输入用户admin，密码p@ssw0rd，以及邮箱（随意）

## 3.push镜像
```
sudo docker push c.io:5000/alpine
```
在浏览器中打开`https://172.18.24.104:5000/v2/_catalog`  
可以看到： 
```json
{"repositories":["alpine"]}
```

## 4.在client端登录
```
sudo docker login c.io:5000
```
输入用户admin，密码p@ssw0rd，以及邮箱（随意）

## 5.pull镜像
```
sudo docker pull c.io:5000/alpine
```