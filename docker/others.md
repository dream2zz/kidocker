杂项
====

## 一次性删除所有关闭的容器
* docker kill $(docker ps -a -q)
* docker rm $(docker ps -a -q)
* docker rm $(docker ps -a | grep Exited)

## 配置 Docker 加速器
```
curl -sSL https://get.daocloud.io/daotools/set_mirror.sh | sh -s http://ed0f9a5e.m.daocloud.io
```

## DNS
```
cat > /etc/resolv.conf << EOF
nameserver 114.114.114.114  
nameserver 8.8.8.8  
nameserver 8.8.4.4  
nameserver 223.5.5.5  
nameserver 223.6.6.6  
EOF
cat /etc/resolv.conf
```
## hosts
wget https://raw.githubusercontent.com/racaljk/hosts/master/hosts -qO /tmp/hosts && sudo sh -c 'cat /tmp/hosts > /etc/hosts'

## Ubuntu设置允许root用户登录

设置开启允许root用户登录方法如下：
1. 修改root密码 `sudo passwd root`
2. 修改ssh配置，找到 `PermitRootLogin` 这项 将其改为` yes`
```
sudo -i
echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
```
3. 保存退出并重启ssh服务`sudo service ssh restart`

## linux下查看某个软件安装到哪些目录

* ubuntu
```
dpkg -L docker-engine
```

* centos
```
rpm -ql docker-engine
```

###  查看当前正在运行的进程。
`ps -ef | grep java`


## Ubuntu Server 19.04配置静态IP


```
vi /etc/netplan/50-cloud-init.yaml
```
```
# This file is generated from information provided by
# the datasource.  Changes to it will not persist across an instance.
# To disable cloud-init's network configuration capabilities, write a file
# /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg with the following:
# network: {config: disabled}
network:
    ethernets:
        ens160:
            addresses:
            - 172.22.24.202/24
            gateway4: 172.22.24.254
            nameservers:
                addresses:
                - 114.114.114.114
    version: 2
```
```
netplan --debug apply
```