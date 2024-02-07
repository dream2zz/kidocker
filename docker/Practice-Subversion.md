实践之SVN 
=========

Subversion 是一款开放源代码的版本控制系统。使用 Subversion，您可以重新加载源代码和文档的历史版本。Subversion 管理了源代码在各个时期的版本。一个文件树被集中放置在文件仓库中。这个文件仓库很像是一个传统的文件服务器，只不过它能够记住文件和目录的每一次变化。

# 一、基础搭建

Subversion + WebDav

## 1、dockerfile
```
FROM ubuntu

RUN apt-get update \
    && apt-get install -y subversion apache2 libapache2-svn apache2-utils \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /srv/* /var/srv/*

ADD apache.conf /etc/apache2/sites-enabled/000-default.conf

RUN addgroup subversion
RUN usermod -G subversion -a www-data

VOLUME /svn
EXPOSE 80

CMD service apache2 start && tail -f /dev/null
```

## 2、apache.conf
```
<VirtualHost *:80>
        ServerAdmin webmaster@localhost
        DocumentRoot /var/www/html

        ErrorLog ${APACHE_LOG_DIR}/error.log
        CustomLog ${APACHE_LOG_DIR}/access.log combined

        <Location />
            DAV svn
            SVNParentPath /svn/repos
            AuthType Basic
            AuthName "Subversion"
            AuthUserFile /svn/passwd
            Require valid-user
        </Location>
</VirtualHost>
```

## 3、构建

```
sudo docker build -t svn .
```

## 4、启动

```
sudo docker run --name svn -d -v /srv/svn:/svn -p 9000:80 svn
```

## 5、新建项目仓库

```
sudo docker run --rm -it -v /srv/svn:/svn svn mkdir -p /svn/repos 
sudo docker run --rm -it -v /srv/svn:/svn svn svnadmin create /svn/repos/project1 
sudo docker run --rm -it -v /srv/svn:/svn svn chown -R www-data /svn/repos/project1
```

## 6、添加用户

```
sudo docker run --rm -it -v /srv/svn:/svn svn htpasswd -c /svn/passwd user1
```

## 7、测试

http://server:9000/project1

# Reference

http://wiki.ubuntu.org.cn/SubVersion