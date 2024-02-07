Installing on Debian
===
If you are using the DEB version of webmin, first download the file from the downloads page , or run the command :
```
wget http://prdownloads.sourceforge.net/webadmin/webmin_1.962_all.deb
```
then run the command :
```
dpkg --install webmin_1.962_all.deb
```
The install will be done automatically to /usr/share/webmin, the administration username set to root and the password to your current root password. You should now be able to login to Webmin at the URL `http://localhost:10000/`. Or if accessing it remotely, replace localhost with your system's IP address.

If Debian complains about missing dependencies, you can install them with the command :
```
apt-get install perl libnet-ssleay-perl openssl libauthen-pam-perl libpam-runtime libio-pty-perl apt-show-versions python unzip
```
If you are installing on Ubuntu and the apt-get command reports that some of the packages cannot be found, edit `/etc/apt/sources.list` and make sure the lines ending with universe are not commented out.

Some Debian-based distributions (Ubuntu in particular) don't allow logins by the root user by default. However, the user created at system installation time can use sudo to switch to root. Webmin will allow any user who has this sudo capability to login with full root privileges.

If you want to connect from a remote server and your system has a firewall installed, see this page for instructions on how to open up port 10000.