#FROM openjdk:8-jdk-alpine
#FROM centos:7
#FROM openjdk:8-jdk
FROM openjdk:8-jdk-slim

ADD filebeat-6.3.0-linux-x86_64.tar.gz /usr/local/

COPY docker-entrypoint /

RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo 'Asia/Shanghai' > /etc/timezone && \
    mv /usr/local/filebeat-6.3.0-linux-x86_64 /usr/local/filebeat && \
    cd /usr/local/filebeat && \
    mkdir data logs && \
    chown -R root:root . && \
    chmod 755 /docker-entrypoint
#ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

ADD xseed-system1-backend-2.0.0.jar /app.jar
EXPOSE 8666

WORKDIR /
ENTRYPOINT ["/docker-entrypoint"]

#ENTRYPOINT ["java","-Djava.security.egd=file:/dev/./urandom","-jar","/app.jar"]
