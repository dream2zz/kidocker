利用容器离线安装linux程序
=======================

本篇以centos为例，描述如何采用容器配置本地包源。

默认情况下，`yum` 在成功下载和安装软件包后，会把下载的文件删掉。这样可以减少 `yum` 占用的磁盘空间。你可以打开缓存，这样 `yum` 将在缓存目录保留下载到的文件。

然后，我们打算将这些文件做到容器里，希望这些文件能作为现场部署的来源，依靠容器的不变性来保障安装的顺利执行。

# 为什么要使用容器？

为了获得干净的环境，安装虚拟机比容器耗时多得多。

在容器里下载了你的程序，只存在你想要的程序以及依赖。

换了一个任务，这个动作可以很轻易的从零开始，不混杂上一次任务的缓存。

# 准备

接下来，我们以软件 `wget` 为例。

编写 `Dockerfile`
```
FROM centos:7.3.1611
MAINTAINER Zhurong <zhurong.b@gsafety.com>

RUN sed -i 's/keepcache=0/keepcache=1/g' /etc/yum.conf

RUN yum install -y wget

VOLUME  /var/cache/yum/

CMD  tail -f /var/log/yum.log
```

构建镜像
```
docker build -t centos-wget .
```

保存镜像
```
docker save centos-wget -o centos-wget
```

# 部署

在现场的服务器先安装docker环境，这个不在本篇介绍。

加载镜像
```
docker load -i centos-wget
```

启动容器
```
docker run --name centos-wget -d centos-wget
```

将容器中的缓存复制到系统中
```
docker cp centos-wget:/var/cache/yum/  /var/cache/
```

采用缓存安装
```
yum -C install wget
```
```
已加载插件：fastestmirror
正在解决依赖关系
--> 正在检查事务
---> 软件包 wget.x86_64.0.1.14-13.el7 将被 安装
--> 解决依赖关系完成

依赖关系解决

============================================================================================================================
 Package                    架构                版本                        源                         大小
============================================================================================================================
正在安装:
 wget                       x86_64              1.14-13.el7                 base                      546 k

事务概要
============================================================================================================================
安装  1 软件包

总计：546 k
安装大小：2.0 M
Is this ok [y/d/N]: y
Downloading packages:
警告：/var/cache/yum/x86_64/7/base/packages/wget-1.14-13.el7.x86_64.rpm: 头V3 RSA/SHA256 Signature, 密钥 ID f4a80eb5: NOKEY
从 file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7 检索密钥
导入 GPG key 0xF4A80EB5:
 用户ID     : "CentOS-7 Key (CentOS 7 Official Signing Key) <security@centos.org>"
 指纹       : 6341 ab27 53d7 8a78 a7c2 7bb1 24c6 a8a7 f4a8 0eb5
 软件包     : centos-release-7-3.1611.el7.centos.x86_64 (@anaconda)
 来自       : /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
是否继续？[y/N]：y
Running transaction check
Running transaction test
Transaction test succeeded
Running transaction
  正在安装    : wget-1.14-13.el7.x86_64                                                                                                                                                              1/1 
  验证中      : wget-1.14-13.el7.x86_64                                                                                                                                                              1/1 

已安装:
  wget.x86_64 0:1.14-13.el7                                                                                                                                                                              

完毕！
```

离线安装完成！