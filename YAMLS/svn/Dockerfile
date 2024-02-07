# docker build --rm -t svn-server .

FROM buildpack-deps:xenial-curl

RUN echo root:p@ssw0rd | chpasswd

RUN apt-get update \
    && apt-get install -y subversion apache2 libapache2-svn apache2-utils openssh-server supervisor \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /srv/* /var/srv/*

RUN mkdir -p /var/lock/apache2 /var/run/apache2 /var/run/sshd /var/log/supervisor

COPY apache.conf /etc/apache2/sites-enabled/000-default.conf
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

RUN addgroup subversion
RUN usermod -G subversion -a www-data

VOLUME /svn
EXPOSE 22 80

CMD /usr/bin/supervisord