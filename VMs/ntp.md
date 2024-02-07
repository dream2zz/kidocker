NTP部署指南
===

<!-- TOC -->

- [1. 服务端](#1-服务端)
    - [1.1. 安装](#11-安装)
    - [1.2. 配置](#12-配置)
- [2. 客户端](#2-客户端)
    - [2.1. 安装](#21-安装)
    - [2.2. 配置](#22-配置)

<!-- /TOC -->

NTP 是通过网络来同步时间的一种 TCP/IP 协议。通常客户端向服务器请求当前的时间，并根据结果来设置其时钟。

# 1. 服务端

## 1.1. 安装

* Ubuntu
```
apt-get update
apt-get install ntp -y
systemctl status ntp
```

* CentOS
```
yum install ntp –y 
systemctl enable ntpd
systemctl start ntpd
systemctl status ntpd
```

## 1.2. 配置

编辑 `/etc/ntp.conf`，增加或移除 `pool`或`server` 行。默认配置有以下服务器：

* Ubuntu
```
......
# Use servers from the NTP Pool Project. Approved by Ubuntu Technical Board
# on 2011-02-08 (LP: #104525). See http://www.pool.ntp.org/join.html for
# more information.
pool 0.ubuntu.pool.ntp.org iburst
pool 1.ubuntu.pool.ntp.org iburst
pool 2.ubuntu.pool.ntp.org iburst
pool 3.ubuntu.pool.ntp.org iburst
......
```

* CentOS
```
......
# Use public servers from the pool.ntp.org project.
# Please consider joining the pool (http://www.pool.ntp.org/join.html).
server 0.centos.pool.ntp.org iburst
server 1.centos.pool.ntp.org iburst
server 2.centos.pool.ntp.org iburst
server 3.centos.pool.ntp.org iburst
......
```

这里是中国常用的NTP服务器，以供参考：
```
210.72.145.44 (国家授时中心服务器IP地址)
202.112.10.36 # 1.cn.pool.ntp.org
59.124.196.83 # 0.asia.pool.ntp.org
s2m.time.edu.cn 北京大学
s2c.time.edu.cn 北京邮电大学
```

`/etc/ntp.conf` 配置内容，下面罗列了来自网络上一些推荐的做法：
```
# 1. 先处理权限方面的问题，包括放行上层服务器以及开放局域网用户来源：
restrict default kod nomodify notrap nopeer noquery     <==拒绝 IPv4 的用户
restrict -6 default kod nomodify notrap nopeer noquery  <==拒绝 IPv6 的用户
restrict 220.130.158.71   <==放行 tock.stdtime.gov.tw 进入本 NTP 的服务器
restrict 59.124.196.83    <==放行 tick.stdtime.gov.tw 进入本 NTP 的服务器
restrict 59.124.196.84    <==放行 time.stdtime.gov.tw 进入本 NTP 的服务器
restrict 127.0.0.1        <==底下两个是默认值，放行本机来源
restrict -6 ::1
restrict 192.168.100.0 mask 255.255.255.0 nomodify <==放行局域网用户来源，或者列出单独IP

# 2. 设定主机来源，请先将原本的 [0|1|2].centos.pool.ntp.org 的设定批注掉：
server 220.130.158.71 prefer  <==以这部主机为最优先的server
server 59.124.196.83
server 59.124.196.84

# 3.默认的一个内部时钟数据，用在没有外部 NTP 服务器时，使用它为局域网用户提供服务：
# server    127.127.1.0     # local clock
# fudge     127.127.1.0 stratum 10

# 4.预设时间差异分析档案与暂不用到的 keys 等，不需要更动它：
driftfile /var/lib/ntp/drift
keys      /etc/ntp/keys
```

通过`ntpq -p`查询状态信息:
```
     remote           refid      st t when poll reach   delay   offset  jitter
==============================================================================
 0.ubuntu.pool.n .POOL.          16 p    -   64    0    0.000    0.000   0.000
 1.ubuntu.pool.n .POOL.          16 p    -   64    0    0.000    0.000   0.000
 2.ubuntu.pool.n .POOL.          16 p    -   64    0    0.000    0.000   0.000
 3.ubuntu.pool.n .POOL.          16 p    -   64    0    0.000    0.000   0.000
 ntp.ubuntu.com  .POOL.          16 p    -   64    0    0.000    0.000   0.000
-ntp.xtom.nl     194.80.204.184   2 u   60   64  377  182.530   -0.921  15.284
+119.28.183.184  100.122.36.4     2 u   59   64  377   29.364   -6.097   7.674
*dns1.synet.edu. 202.118.1.46     2 u    4   64  377   38.284    1.065   1.878
+202.108.6.95 (x 10.69.2.34       2 u   63   64  377   24.593    1.712   1.326
-chilipepper.can 17.253.34.125    2 u   33   64  377  231.826   -1.005   4.757
-pugot.canonical 17.253.34.125    2 u   31   64  377  228.914   -0.642   8.029
```

# 2. 客户端

## 2.1. 安装

与服务端一样

## 2.2. 配置

编辑 `/etc/ntp.conf`，删除默认配置，增加下面的内容

```
server 172.22.24.101 prefer iburst # 172.22.24.101为上面服务端的IP
```

通过`ntpq -p`查询状态信息:
```
     remote           refid      st t when poll reach   delay   offset  jitter
==============================================================================
 172.22.24.101   119.28.183.184   3 u    1   64    1    0.323    1.390   0.000
```


