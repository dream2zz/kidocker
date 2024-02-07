FROM jenkins:2.46.1

USER root

RUN  curl -sL https://deb.nodesource.com/setup_7.x | bash - && apt-get install -y apt-utils nodejs git  

RUN  /usr/local/bin/install-plugins.sh git git-client gitlab-plugin scm-api gradle javadoc jira nodejs gitlab-hook kubernetes-ci docker-build-step

# docker build --rm  -t k8s-jenkins .