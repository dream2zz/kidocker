FROM openjdk:8-jdk-alpine

#RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    #echo 'Asia/Shanghai' > /etc/timezone

ADD xseed-system1-backend-2.0.0.jar /app.jar

EXPOSE 8666

ENTRYPOINT ["java","-Djava.security.egd=file:/dev/./urandom","-jar","/app.jar"]
