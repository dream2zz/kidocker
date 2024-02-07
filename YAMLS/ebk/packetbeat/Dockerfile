FROM openjdk:8-jdk-slim

ADD filebeat-6.3.0-linux-x86_64.tar.gz /usr/local/
ADD packetbeat-6.3.0-linux-x86_64.tar.gz /usr/local/

COPY docker-entrypoint /

RUN mv /usr/local/filebeat-6.3.0-linux-x86_64 /usr/local/filebeat && \
    cd /usr/local/filebeat && \
    mkdir data logs && \
    chown -R root:root . && \
    mv /usr/local/packetbeat-6.3.0-linux-x86_64 /usr/local/packetbeat && \
    cd /usr/local/packetbeat && \
    mkdir data logs && \
    chown -R root:root . && \
    chmod 755 /docker-entrypoint

ADD xseed-system1-backend-2.0.0.jar /app.jar
EXPOSE 8666

WORKDIR /
ENTRYPOINT ["/docker-entrypoint"]

