Installing the RPM
===
If you are using the RPM version of Webmin, first download the file from the downloads page , or run the command :

```
wget http://prdownloads.sourceforge.net/webadmin/webmin-1.962-1.noarch.rpm
```
then install optional dependencies with :
```
yum -y install perl perl-Net-SSLeay openssl perl-IO-Tty perl-Encode-Detect
```
and then run the command :
```
rpm -U webmin-1.962-1.noarch.rpm
```
The rest of the install will be done automatically to the directory /usr/libexec/webmin, the administration username set to root and the password to your current root password. You should now be able to login to Webmin at the URL` http://localhost:10000/ `. Or if accessing it remotely, replace localhost with your system's IP address.

If you want to connect from a remote server and your system has a firewall installed, see this page for instructions on how to open up port 10000.