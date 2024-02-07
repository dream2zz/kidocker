容器技术工作总结
===============

# 1 过程

## 1.1 容器技术基础
> 2016-02-18 ~ 2016-03-09 15天 。  
对官方WIKI翻译，并归档于gitlab上。

任务|时间
----|---
技术概览&环境搭建|4D
Docker Engine|3D
Docker Compose|3D
Docker Swarm|5D

## 1.2 容器技术实践
> 2016-03-29 ~ 2016-04-13 12天 。  
总结私有镜像的Dockerfile；归档部署文档；在内网中部署一个实例。

任务|时间
----|---
cnpm | 5D
Jira | 1D
SVN | 1D
Gitlab | 2D (chencai)
GitlabCI | 3D
Jenkins | 1D
Nexus | 1D

## 1.3 管理工具及流程定义
> 2016-03-21 ~ 2016-03-30 8天。  
归档部署文档；在内网中部署一个实例。

任务|时间
----|---
DockerUI |1D
DockerRegistryUI |1D
Consul |5D
kubernetes |1D
流程定义 |1D

# 2 问题

## 2.1 cnpm

并不是所有能在linux上成功运行的应用，就能在容器中运行。
cnpm在ubuntu的容器中运行虽然能成功，但是容器自身的路由并不能成功让外部访问cnpm。

解决这个问题虽然能靠nginx做一个反向代理，但最好的结果是淘宝能提供官方镜像。

## 2.2 alpine vs ubuntu
两者的包管理不同，alpine采用的是apk，ubuntu采用的是debian系列的apt。这两者的区别给实践带来很多麻烦。

## 2.3 Swarm and HA
Docker Swarm，是docker-engine在各个主机上部署的容器集群，应用的集群在容器集群的层次之上。
目前还需要大量实践去填补应用层面的高可用性。

# 3 后续

详见 【[容器技术实践总结 4.后续](http://172.18.3.103/Hakugei/docker/wikis/Practice-summary#4-%E5%90%8E%E7%BB%AD)】
