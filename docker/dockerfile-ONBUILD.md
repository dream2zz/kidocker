Dockerfile 指令 ONBUILD介绍
====

ONBUILD指令可以为镜像添加触发器。其参数是任意一个Dockerfile 指令。

当我们在一个Dockerfile文件中加上ONBUILD指令，该指令对利用该Dockerfile构建镜像（比如为A镜像）不会产生实质性影响。

但是当我们编写一个新的Dockerfile文件来基于A镜像构建一个镜像（比如为B镜像）时，这时构造A镜像的Dockerfile文件中的ONBUILD指令就生效了，在构建B镜像的过程中，首先会执行ONBUILD指令指定的指令，然后才会执行其它指令。

需要注意的是，如果是再利用B镜像构造新的镜像时，那个ONBUILD指令就无效了，也就是说只能再构建子镜像中执行，对孙子镜像构建无效。其实想想是合理的，因为在构建子镜像中已经执行了，如果孙子镜像构建还要执行，相当于重复执行，这就有问题了。

利用ONBUILD指令,实际上就是相当于创建一个模板镜像，后续可以根据该模板镜像创建特定的子镜像，需要在子镜像构建过程中执行的一些通用操作就可以在模板镜像对应的dockerfile文件中用ONBUILD指令指定。 从而减少dockerfile文件的重复内容编写。

---

我们来看一个简单例子。

1、先编写一个Dockerfile文件，内容如下：
```
#test
FROM ubuntu
MAINTAINER hello
ONBUILD RUN mkdir mydir
```
利用上面的dockerfile文件构建镜像： docker build -t imagea .

利用imagea镜像创建容器： docker run --name test1 -it imagea /bin/bash

我们发现test1容器的根目录下并没有mydir目录。说明ONBUILD指令指定的指令并不会在自己的构建中执行。

2、再编写一个新的Dockerfile文件，内容 如下
```
#test
FROM imagea
MAINTAINER hello1
```
注意，该构建准备使用的基础镜像是上面构造出的镜像imagea

利用上面的dockerfile文件构建镜像： docker build -t imageb .

利用imagea镜像创建容器： docker run --name test2 -it imageb /bin/bash

我们发现test2容器的根目录下有mydir目录，说明触发器执行了。 这个其实从构建imageb的输出日志就可看出。日志如下：
```
xxx@ubuntu:~/myimage$ docker build -t imageb .
Sending build context to Docker daemon 15.87 kB
Step 1 : FROM imagea
# Executing 1 build trigger...
Step 1 : RUN mkdir mydir
 ---> Running in e16c35c94b03
 ---> 4b393d1610a6
Removing intermediate container e16c35c94b03
Step 2 : MAINTAINER hello1
 ---> Running in c7b0312516ea
 ---> 0f63b8e04d82
Removing intermediate container c7b0312516ea
Successfully built 0f63b8e04d82
```
我们可以看出，FROM指令执行之后，就立即执行的是触发器（ONBUILD指令指定的指令）