# FROM nginx
FROM centos:latest
MAINTAINER Frédéric Haziza <daz@bils.se>

# Install EPEL and updates
RUN yum install -y epel-release
RUN yum -y update
RUN yum clean all

# Install Nginx
RUN yum install -y nginx

#VOLUME ["/usr/share/nginx/html"]

EXPOSE 80
# EXPOSE 443

CMD ["nginx", "-g", "daemon off;"]
