![](images\Bamboo.png)

# 1 Running Bamboo Server with a Remote Agent
If you want to run Bamboo Server and Agent containers on one host (in one Docker engine), you will need to create a Docker network for them:
```
$> docker network create bamboo
```
You can start Bamboo Server and Agent using following commands:
```
$> docker run -v bambooVolume:/var/atlassian/application-data/bamboo --name bamboo-server --network bamboo --hostname bamboo-server --init -d -p 8085:8085 atlassian/bamboo-server
$> docker run -v bambooAgentVolume:/home/bamboo/bamboo-agent-home --name bamboo-agent --network bamboo --hostname bamboo-agent --init -d atlassian/bamboo-agent-base http://bamboo-server:8085
```

# 2 Extending base image
This Docker image contains only minimal setup to run a Bamboo agent which might not be sufficient to run your builds. If you need additional capabilities you can extend the image to suit your needs.

Example of extending the agent base image by Maven and Git:
```
FROM atlassian/bamboo-agent-base
USER root
RUN apt-get update && \
    apt-get install maven -y && \
    apt-get install git -y

USER ${BAMBOO_USER}
RUN ${BAMBOO_USER_HOME}/bamboo-update-capability.sh "system.builder.mvn3.Maven 3.3" /usr/share/maven
RUN ${BAMBOO_USER_HOME}/bamboo-update-capability.sh "system.git.executable" /usr/bin/git
```