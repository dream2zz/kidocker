实践之Gitlab
==================

本文主要参照[Dockerizing a gitlab](http://192.168.3.103/Hakugei/docker/wikis/Dockerizing-a-gitlab)
里的过程，在 docker 环境中作出实践。

# 1、准备
* [Docker 环境](http://192.168.3.103/Hakugei/docker/wikis/Install-by-script)
* 如果公司的私有环境中已有下载好的镜像，可以参照[配置docker client端](http://192.168.3.103/Hakugei/docker/wikis/Deploying-a-registry-server#%E4%B8%89%E9%AA%8C%E8%AF%81%E6%B5%8B%E8%AF%95)的操作PULL所需镜像，需注意修改命令中的镜像名称。

# 2、运行Gitlab容器
```
sudo docker run --detach \
    --hostname gitlab.example.com \
    --publish 443:443 --publish 80:80 --publish 22:22 \
    --name gitlab-cici \
    --restart always \
    --volume /srv/gitlab/config:/etc/gitlab \
    --volume /srv/gitlab/logs:/var/log/gitlab \
    --volume /srv/gitlab/data:/var/opt/gitlab \
    gitlab/gitlab-ce:latest
```
注意事项：  
* 需要把hostname的`gitlab.example.com`换成IP地址
* name gitlab-cici这里的`gitlab-cici`是容器的名称，请自行命名
* 选择Gitlab的版本：可将`gitlab/gitlab-ce:latest`中的`latest`换成你所需要的Gitlab的版本号；  
或者将`gitlab/gitlab-ce:latest`替换成本地镜像的名称
* 如果端口号有冲突，请修改端口号

# 3、Docker Gitlab的备份及还原
## 3.1、Docker Gitlab备份
官方Omnibus Gitlab安装包的备份命令如下：（目前我们3.103的GITLAB服务器使用的就是这个安装包）
```
sudo gitlab-rake gitlab:backup:create
```

Docker Gitlab的备份命令需要在基础的命令前面加上`sudo docker exec -it gitlab-cici`，意思是进入一个容器，注意这里的`gitlab-cici`请替换成你容器的名称。
```
sudo docker exec -it gitlab-cici gitlab-rake gitlab:backup:create
```

输出如下图：  
![backup](/uploads/de6e38b13cf5670eeb075d23c59a9b3e/backup.bmp)

xxxxx_gitlab_backup.tar就是Gitlab的备份文件，默认存放在`/srv/gitlab/data`下的`backups`里；可根据需要复制存放到其他的备份服务器中。`特别注意事项`存放备份文件时需注明这个备份文件是基于Gitlab哪个版本备份的。  
![data](/uploads/ddb27e2cc7c7a904ad561187c6626ce2/data.bmp)

## 3.1、Docker Gitlab还原
官方Omnibus Gitlab的还原命令步骤如下：  

First make sure your backup tar file is in /var/opt/gitlab/backups (or wherever gitlab_rails['backup_path'] points to).
```
sudo cp 1459241351_gitlab_backup.tar /var/opt/gitlab/backups/
```  

Next, restore the backup by running the restore command. You need to specify the timestamp of the backup you are restoring.

* Stop processes that are connected to the database  

```
sudo gitlab-ctl stop unicorn
sudo gitlab-ctl stop sidekiq
```
* This command will overwrite the contents of your GitLab database!  

```
sudo gitlab-rake gitlab:backup:restore BACKUP=1459241351
```
* Start GitLab  

```
sudo gitlab-ctl start
```
* Check Gitlab  

```
sudo gitlab-rake gitlab:check SANITIZE=true
```

在Docker Gitlab下，将备份文件拷贝到`/srv/gitlab/data/backups`里；然后分步执行以下还原命令（就是在上面的基础命令前面加上`sudo docker exec -it gitlab-cici`）
```
sudo docker exec -it gitlab-cici gitlab-ctl stop unicorn
sudo docker exec -it gitlab-cici gitlab-ctl stop sidekiq
sudo docker exec -it gitlab-cici gitlab-rake gitlab:backup:restore BACKUP=1459241351
sudo docker exec -it gitlab-cici gitlab-ctl start
sudo docker exec -it gitlab-cici gitlab-rake gitlab:check SANITIZE=true
```
注意事项：  
* 还原的 Gitlab容器版本必须与备份文件容器版本保持一致
* BACKUP=xxxxxxx后面的编号是备份文件xxxxx_gitlab_backup.tar前的编号，根据实际情况更换。
* `sudo docker exec -it gitlab-cici`的`gitlab-cici`记住更换成你的容器名称。  

备份完成的输出图如下：  
![restore](/uploads/40dbff6338c2928d952346844474fa02/restore.bmp)  

check完成的输出图如下：  
![check](/uploads/71d90d1d046780048c3cdbbbbf36dcc1/check.bmp)

# 4、Docker Gitlab的更新
将Docker Gitlab更新到新版本我们需要做：  

* 停止正在运行的 Gitlab容器  

```
sudo docker stop gitlab-cici
```
* 移除 Gitlab容器  

```
sudo docker rm gitlab-cici
```
* 拉取新版本的 Gitlab镜像  (请关注`https://hub.docker.com/u/gitlab/`这个地址，查看版本更新情况）

```
sudo docker pull gitlab/gitlab-ce:latest
```
* 用原来的配置创建Gitlab容器  

```
sudo docker run --detach \
--hostname gitlab.example.com \
--publish 443:443 --publish 80:80 --publish 22:22 \
--name gitlab-cici \
--restart always \
--volume /srv/gitlab/config:/etc/gitlab \
--volume /srv/gitlab/logs:/var/log/gitlab \
--volume /srv/gitlab/data:/var/opt/gitlab \
gitlab/gitlab-ce:latest
```
步骤样图如下：  
![Upgrade](/uploads/ab1d13d5b1e6af56c4759da7ce5b2940/Upgrade.bmp)

原来的版本是8.6.0,更新后为8.6.1，如下图  
![new](/uploads/e8a03b3780bd39016f43547e7fe5706b/new.bmp)  

# 5、将Omnibus Gitlab 的数据迁移到Docker Gitlab上
请保证两边服务器使用的版本是一致（测试时我这边统一版本是8.6.1）  
* 对Omnibus Gitlab的数据进行备份；备份前我停止了数据连接。  
 
1.停止数据连接  

```
sudo gitlab-ctl stop unicorn
sudo gitlab-ctl stop sidekiq
```  

2.备份  

```
sudo gitlab-rake gitlab:backup:create
```  

输出图如下：  
![OM01](/uploads/08d462842ae43ed8c199c3e41773102e/OM01.bmp)  

3.将备份文件拷贝出来，Omnibus Gitlab的备份数据存放在`/srv/gitlab/data/backups`路径中。

* 在Docker Gitlab还原Omnibus Gitlab的备份数据。  

1.将Omnibus Gitlab的备份数据拷贝到Docker Gitlab的`/srv/gitlab/data/backups`下  
  
![DC01](/uploads/304cf0fd394c010a7a271a1c5112da20/DC01.bmp)  

2.还原的操作请参见`章节3`的Docker Gitlab还原步骤，测试的输出图如下：  
停止数据链接并备份  

![DC02](/uploads/6a3c2da6948f37b1a39085c3a9225973/DC02.png)  
备份完成  
![DC03](/uploads/fcad9c37ed7cd6856bd2cf54fe9128c8/DC03.png)  
启动服务并check  
![DC04](/uploads/fb61c24bc01e9428447be9db93bbd737/DC04.png)  
check成功  
![check02](/uploads/243609365bf3ab4b7abe70839f9abf18/check02.bmp)  
迁移数据完成，打开网页检查。两个服务器的比较图：  
![DC06](/uploads/1c105f3472d685ef866bc42aa202eb87/DC06.png)
