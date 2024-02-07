lsyncd
======

> lsyncd实时同步搭建指南——取代rsync+inotify  
https://segmentfault.com/a/1190000002737213  
如何实时同步大量小文件  
http://ju.outofmemory.cn/entry/87237

# 安装
```
yum install epel-release -y
yum install rsync lsyncd -y
```

# 配置
```
rpm -ql lsyncd
```
> /etc/logrotate.d/lsyncd  
/etc/lsyncd.conf  
/etc/sysconfig/lsyncd  
/usr/bin/lsyncd  
/usr/lib/systemd/system/lsyncd.service  
/usr/share/doc/lsyncd-2.1.5  
/usr/share/doc/lsyncd-2.1.5/COPYING  
/usr/share/doc/lsyncd-2.1.5/ChangeLog  
/usr/share/doc/lsyncd-2.1.5/examples  
/usr/share/doc/lsyncd-2.1.5/examples/lbash.lua  
/usr/share/doc/lsyncd-2.1.5/examples/lecho.lua  
/usr/share/doc/lsyncd-2.1.5/examples/lgforce.lua  
/usr/share/doc/lsyncd-2.1.5/examples/limagemagic.lua  
/usr/share/doc/lsyncd-2.1.5/examples/lpostcmd.lua  
/usr/share/doc/lsyncd-2.1.5/examples/lrsync.lua  
/usr/share/doc/lsyncd-2.1.5/examples/lrsyncssh.lua  
/usr/share/man/man1/lsyncd.1.gz

```
vi /etc/lsyncd.conf
```
```Lua
settings {
    logfile         ="/root/lsyncd.`date +%Y%m%d`.log",
    statusFile      ="/root/lsyncd.status",
    logfacility     = daemon,
    nodaemon        = false ,
    inotifyMode     = "CloseWrite",
    statusIntervall = 20,
    maxDelays       = 10,
    maxProcesses    = 10
    }

sync {
    default.rsync,
    source          = "/root/sharedata",
    target          = "/root/backupdata",
    delay           = 5, 
    delete          = true,
    rsync           = {
        binary      = "/usr/bin/rsync",
        archive     = true,
        compress    = true,
        verbose     = true
        }
    }
```

# 启动

```
lsyncd /etc/lsyncd.conf
```

# 关闭
```
ps -ef | grep lsyncd
kill <pid>
```