实践之Nexus搭建Maven私服
======================

Nexus 是Maven仓库管理器，如果你使用Maven，你可以从Maven中央仓库下载所需要的构件（artifact），
但这通常不是一个好的做法，你应该在本地架设一个Maven仓库服务器，在代理远程仓库的同时维护本地仓库，
以节省带宽和时间，Nexus就可以满足这样的需要。此外，他还提供了强大的仓库管理功能，构件搜索功能，
它基于REST，友好的UI是一个extjs的REST客户端，它占用较少的内存，基于简单文件系统而非数据库。
这些优点使其日趋成为最流行的Maven仓库管理器。

# 一、基础搭建

## 1、先决条件
* [Docker 环境](http://192.168.3.103/Hakugei/docker/wikis/Install-by-script)

## 2、安装
```
sudo mkdir -p /srv/nexus/data && sudo chmod 777 /srv/nexus/data
```
```
sudo docker run --name nexus -d \
    -p 8081:8081 \
    -v /srv/nexus/data:/sonatype-work \
    sonatype/nexus
```
现在你可以访问nexus了： http://server:8081

默认账户密码： admin 、admin123

## 3、备份
在上面的安装命令中，我们指定了`/srv/nexus/data`用于挂载容器的卷。所以，随时备份这个目录即可。

## 4、升级
升级前先备份。
```
sudo docker stop nexus
sudo docker rm nexus
sudo docker run --name nexus -d \
    -p 8081:8081 \
    -v /srv/nexus/data:/sonatype-work \
    sonatype/nexus
```

# 二、仓库备份
打开http://server:8081 ，
按照 [nexus 站点仓库的配置](http://192.168.3.103/vNextDevTechs/Java/wikis/how-to-build-private-maven-repository#37-nexus-%E7%AB%99%E7%82%B9%E4%BB%93%E5%BA%93%E7%9A%84%E9%85%8D%E7%BD%AE)。

进行一段时间之后，我们查看一下nexus挂载的卷的文件夹的大小:
```
$ sudo du -h --max-depth=1 /srv/nexus/data
852K	/srv/nexus/data/felix-cache
116K	/srv/nexus/data/logs
12K	/srv/nexus/data/db
8.0K	/srv/nexus/data/backup
26M	/srv/nexus/data/storage
56K	/srv/nexus/data/.java
8.0K	/srv/nexus/data/orient
272M	/srv/nexus/data/indexer
4.0K	/srv/nexus/data/plugin-repository
112K	/srv/nexus/data/timeline
8.0K	/srv/nexus/data/.oracle_jre_usage
636K	/srv/nexus/data/health-check
56K	/srv/nexus/data/nuget
52K	/srv/nexus/data/conf
299M	/srv/nexus/data
```
可以发现，索引文件目录包含在应用文件目录中。所以备份nexus挂载的卷，就能备份这些资源仓库。

# sonatype/docker-nexus

Docker images for Sonatype Nexus Repository Manager 2 with the Oracle JDK.
For Nexus Repository Manager 3, please refer to https://github.com/sonatype/docker-nexus3

To build:
```
# docker build --rm --tag sonatype/nexus oss/
# docker build --rm --tag sonatype/nexus-pro pro/
```

To run (if port 8081 is open on your host):

```
# docker run -d -p 8081:8081 --name nexus sonatype/nexus:oss
```

To determine the port that the container is listening on:

```
# docker ps nexus
```

To test:

```
$ curl http://localhost:8081/service/local/status
```

To build, copy the Dockerfile and do the build:

```
$ docker build --rm=true --tag=sonatype/nexus .
```


## Notes

* Default credentials are: `admin` / `admin123`

* It can take some time (2-3 minutes) for the service to launch in a
new container.  You can tail the log to determine once Nexus is ready:

```
$ docker logs -f nexus
```

* Installation of Nexus is to `/opt/sonatype/nexus`.  Notably:
  `/opt/sonatype/nexus/conf/nexus.properties` is the properties file.
  Parameters (`nexus-work` and `nexus-webapp-context-path`) definied
  here are overridden in the JVM invocation.

* A persistent directory, `/sonatype-work`, is used for configuration,
logs, and storage. This directory needs to be writable by the Nexus
process, which runs as UID 200.

* Environment variables can be used to control the JVM arguments

  * `CONTEXT_PATH`, passed as -Dnexus-webapp-context-path.  This is used to define the
  URL which Nexus is accessed.
  * `MAX_HEAP`, passed as -Xmx.  Defaults to `768m`.
  * `MIN_HEAP`, passed as -Xms.  Defaults to `256m`.
  * `JAVA_OPTS`.  Additional options can be passed to the JVM via this variable.
  Default: `-server -XX:MaxPermSize=192m -Djava.net.preferIPv4Stack=true`.
  * `LAUNCHER_CONF`.  A list of configuration files supplied to the
  Nexus bootstrap launcher.  Default: `./conf/jetty.xml ./conf/jetty-requestlog.xml`

  These can be user supplied at runtime to control the JVM:

  ```
  $ docker run -d -p 8081:8081 --name nexus -e MAX_HEAP=768m sonatype/nexus
  ```


### Persistent Data

There are two general approaches to handling persistent
storage requirements with Docker. See [Managing Data in
Containers](https://docs.docker.com/userguide/dockervolumes/) for
additional information.

  1. *Use a data volume container*.  Since data volumes are persistent
  until no containers use them, a container can be created specifically for 
  this purpose.  This is the recommended approach.  

  ```
  $ docker run -d --name nexus-data sonatype/nexus echo "data-only container for Nexus"
  $ docker run -d -p 8081:8081 --name nexus --volumes-from nexus-data sonatype/nexus
  ```

  2. *Mount a host directory as the volume*.  This is not portable, as it
  relies on the directory existing with correct permissions on the host.
  However it can be useful in certain situations where this volume needs
  to be assigned to certain underlying storage.  

  ```
  $ mkdir /some/dir/nexus-data && chown -R 200 /some/dir/nexus-data
  $ docker run -d -p 8081:8081 --name nexus -v /some/dir/nexus-data:/sonatype-work sonatype/nexus
  ```


### Adding Nexus Plugins

Creating a docker image based on `sonatype/nexus` is the suggested
process: plugins should be expanded to `/opt/sonatype/nexus/nexus/WEB-INF/plugin-repository`.
See https://github.com/sonatype/docker-nexus/issues/9 for an example
concerning the Nexus P2 plugins.
# sonatype/nexus3

A Dockerfile for Sonatype Nexus Repository Manager 3, based on CentOS.

To run, binding the exposed port 8081 to the host.

```
$ docker run -d -p 8081:8081 --name nexus sonatype/nexus3
```

To test:

```
$ curl -u admin:admin123 http://localhost:8081/service/metrics/ping
```

To (re)build the image:

Copy the Dockerfile and do the build-

```
$ docker build --rm=true --tag=sonatype/nexus3 .
```


## Notes

* Default credentials are: `admin` / `admin123`

* It can take some time (2-3 minutes) for the service to launch in a
new container.  You can tail the log to determine once Nexus is ready:

```
$ docker logs -f nexus
```

* Installation of Nexus is to `/opt/sonatype/nexus`.  

* A persistent directory, `/nexus-data`, is used for configuration,
logs, and storage. This directory needs to be writable by the Nexus
process, which runs as UID 200.

* Three environment variables can be used to control the JVM arguments

  * `JAVA_MAX_HEAP`, passed as -Xmx.  Defaults to `1200m`.

  * `JAVA_MIN_HEAP`, passed as -Xms.  Defaults to `1200m`.

  * `EXTRA_JAVA_OPTS`.  Additional options can be passed to the JVM via
  this variable.

  These can be used supplied at runtime to control the JVM:

  ```
  $ docker run -d -p 8081:8081 --name nexus -e JAVA_MAX_HEAP=768m sonatype/nexus3
  ```


### Persistent Data

There are two general approaches to handling persistent storage requirements
with Docker. See [Managing Data in Containers](https://docs.docker.com/userguide/dockervolumes/)
for additional information.

  1. *Use a data volume container*.  Since data volumes are persistent
  until no containers use them, a container can created specifically for 
  this purpose.  This is the recommended approach.  

  ```
  $ docker run -d --name nexus-data sonatype/nexus3 echo "data-only container for Nexus"
  $ docker run -d -p 8081:8081 --name nexus --volumes-from nexus-data sonatype/nexus3
  ```

  2. *Mount a host directory as the volume*.  This is not portable, as it
  relies on the directory existing with correct permissions on the host.
  However it can be useful in certain situations where this volume needs
  to be assigned to certain specific underlying storage.  

  ```
  $ mkdir /some/dir/nexus-data && chown -R 200 /some/dir/nexus-data
  $ docker run -d -p 8081:8081 --name nexus -v /some/dir/nexus-data:/nexus-data sonatype/nexus3
  ```