实践之cnpm
==========

cnpm是企业内部搭建npm镜像和私有npm仓库的开源方案。

# 一、基础搭建

## 1、先决条件
* [Docker 环境](http://192.168.3.103/Hakugei/docker/wikis/Install-by-script)
* [Docker Compose](http://192.168.3.103/Hakugei/docker/wikis/Docker-Compose-Install)

## 1 cnpm0 

1.1 Dockerfile
```
FROM mysql
ADD  db.sql .
```

1.2 build
```
docker build -t cnpm0 .
```

2 cnpm1 

2.1 run cnpm0
```
docker run -d --name cnpm0 -e MYSQL_ROOT_PASSWORD=p@ssw0rd -e MYSQL_DATABASE=cnpmjs cnpm0
```

2.2 Container Shell Access
```
docker exec -it cnpm0 bash
```

2.3 create mysql tables
```
mysql -u root -p

mysql> use cnpmjs;
mysql> source /db.sql
```

2.4 commit
```
docker ps -a

docker commit <container_id> cnpm1
```

3 cnpm2

3.1 Dockerfile
```
FROM  cnpm1

RUN curl --silent --location https://rpm.nodesource.com/setup_6.x | bash -

RUN yum update && yum install -y  nodejs gcc-c++ make && rm -rf /var/cache/yum/*
  
RUN npm install -g --build-from-source \
  --registry=https://registry.npm.taobao.org \
  --disturl=https://npm.taobao.org/mirrors/node \
  cnpmjs.org cnpm 
  
ADD config.js .

EXPOSE 7001 7002

CMD  ./root/node_modules/cnpmjs.org/bin/nodejsctl start && tail -f 
```

3.2 build
```
docker build -t cnpm2 .
```

## 4、启动

```

```
## 5、使用
可以打开 http://server:9000 查看管理端。

配置NPM的私有源地址
```
npm config edit
```
在弹出的文件中，加入如下内容：
```
registry=http://server:7001/
```
IP地址为部署cnpm服务所在机器的IP地址。
通过如下指令可检查配置是否成功
```
npm config list
```