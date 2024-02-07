Docker中运行 asp.net-core 应用
=============================

这个例子的目的是向您展示如何通过使用 Dockerfile来构建自己的docker镜像。  
我们将在`microsoft/aspnet:1.0.0-rc1-update1`上运行一个简单 asp.net-core webapi应用。

# 生成一个 asp.net-core 应用

[如何生成](http://192.168.3.103/docker/docker/wikis/Install-by-script)。

这里，我们选择 `WebAPIApplication`

# 创建Dockerfile
在你的工程里，需要包含一个Dockerfile文件，其内容如下：
```
FROM microsoft/aspnet:1.0.0-rc1-update1

RUN printf "deb http://ftp.us.debian.org/debian jessie main\n" >> /etc/apt/sources.list
RUN apt-get -qq update && apt-get install -qqy sqlite3 libsqlite3-dev && rm -rf /var/lib/apt/lists/*

COPY . /app
WORKDIR /app
RUN ["dnu", "restore"]

EXPOSE 5000/tcp
ENTRYPOINT ["dnx", "-p", "project.json", "web"]
```

# 创建镜像
```
sudo docker build -t aspnet-core-test .
```

# 运行镜像
```
sudo docker run -t -d -p 9000:5000 aspnet-core-test
```

# 测试

现在可以通过访问http://myapp-server-ip:9000 来查看你的应用了。