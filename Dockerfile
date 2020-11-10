FROM centos:8

USER root

RUN yum -y install python3 python3-flask

WORKDIR /app

COPY . /app

USER 1001

ENTRYPOINT ["python3"]

CMD ["app.py"]
