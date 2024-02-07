Docker中运行Node.js web应用
==========================

<!-- TOC -->

- [创建Node.js应用](#创建nodejs应用)
- [创建Dockerfile](#创建dockerfile)
- [创建你的个人镜像](#创建你的个人镜像)
- [运行镜像](#运行镜像)
- [测试](#测试)

<!-- /TOC -->

这个例子的目的是向您展示如何通过使用 Dockerfile来构建自己的docker镜像。  
我们将在名为`node`的镜像容器上运行一个简单 node.js web应用并输出'hello word'。

# 创建Node.js应用

首先，先创建一个文件存放目录src。然后创建package.json文件来描述你的应用程序和依赖关系：
```json
{
  "name": "myapp",
  "version": "0.0.0",
  "private": true,
  "dependencies": {
    "express": "^4.13.4"
  }
}
```
然后，创建一个 app.js 文件使用 Express.js 框架来创建一个web应用程序:
```js
var express = require('express');

// Constants
var PORT = 8080;

// App
var app = express();
app.get('/', function (req, res) {
  res.send('Hello world\n');
});

app.listen(PORT);
console.log('Running on http://localhost:' + PORT);
```

# 创建Dockerfile

创建一个空文件叫Dockerfile，使用你喜欢的编辑器打开Dockerfile。

接下来，定义构建自己镜像的父级镜像。在这里我们使用 Docker Hub 中 `alpine` 镜像：
```
FROM    alpine
```
由于这是一个非常精简的镜像，所以我们还需要安装nodejs环境：
```
RUN apk add --update nodejs && rm -rf /var/cache/apk/*
```
将你的应用程序源代码添加到你的Docker镜像中，使用COPY指令：
```
COPY    . /app
WORKDIR /app
```
使用npm安装你的应用程序依赖：
```
RUN     npm install
```
应用程序绑定到端口8080，您将使用EXPOSE指令对 docker 端口进程映射：
```
EXPOSE  8080
```
最后，定义命令，使用 CMD 定义运行时的node服务和应用 app.js 的路径：
```
CMD ["node", "app.js"]
```
你的Dockerfile现在看起来像如下这样：
```
FROM    alpine

RUN     apk add --update nodejs && rm -rf /var/cache/apk/*

COPY    . /app
WORKDIR /app

RUN     npm install

EXPOSE  8080
CMD     ["node", "app.js"]
```

# 创建你的个人镜像

到你的 Dockerfile 目录下，运行命令来构建镜像。-t 参数给镜像添加标签，为了让我们在 docker images 命令更容易查找到它：
```
$ docker build -t myapp .
```
你的镜像现在将在列表中：
```
$ docker images ls
# Example
REPOSITORY          TAG         ID              CREATED
node                latest      539c0211cd76    8 weeks ago
myapp               latest      d64d3505b0d2    2 hours ago
```

# 运行镜像

使用 -d 参数来运行你的镜像并将容器在后台运行。使用 -p 参数来绑定一个公共端口到私有容器端口上。运行你之前构建的镜像：
```
$ docker run -p 9000:8080 -d myapp
```
查看运行中的进程：
```
$ docker container ls
# Example
CONTAINER ID        IMAGE               COMMAND             CREATED             STATUS              PORTS                    NAMES
f8f2b3341927        myapp               "node app.js"       33 seconds ago      Up 33 seconds       0.0.0.0:9000->8080/tcp   dreamy_rosalind
```

# 测试

现在可以通过访问http://myapp-server-ip:9000 来查看你的应用了。
