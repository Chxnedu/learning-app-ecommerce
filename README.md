# Introduction

This challenge leverages Kubernetes and Containerization using Docker to deploy a php e-commerce website. Docker is used to encapsulate the application and its environment, ensuring it runs consistently everywhere, and Kubernetes automates deployment, scaling and management of the application.

I decided to try this project after taking the Certified Kubernetes Administrator course on KodeKloud, to test and validate my skills and all I learned. This article will cover how I approached the challenge, the decisions I took and the reasons for them, and all the new things I learned during the course of this challenge.

---

# Understanding the Challenge

## Prerequisites

- **Docker and Kubernetes (kubectl) CLI Tools**: Essential for building and pushing Docker images, and managing Kubernetes resources.
- **Cloud Provider Account**: Access to AWS, Azure, or GCP for creating a Kubernetes cluster
- **GitHub Account**: For version control and implementing CI/CD pipelines
- **E-commerce Application Source Code and DB Scripts**: Available at [kodekloudhub/learning-app-ecommerce](https://github.com/kodekloudhub/learning-app-ecommerce)

---

# Containerizing The Application

## The Web App

The application uses a two-tier architecture; the client tier and data tier (database). The application will be built into an image using a Dockerfile, while the database will use the default MariaDB image.
I wrote a Dockerfile for the application, following best practices.

```Dockerfile
# base image used for the application
FROM php:7.4-apache

# update packages and install the mysqli extension
RUN apt-get update && docker-php-ext-install mysqli && docker-php-ext-enable mysqli

# copy application code into the image
COPY /app /var/www/html/

# expose the port where the application will run
EXPOSE 80
```

Build the image and test it locally to ensure it works before pushing it to Docker Hub.

```bash
docker build -t chxnedu/ecommerce-app:v1 .

docker push chxnedu/ecommerce-app:v1
```

## The Database

I utilized environment variables to configure the database name, user and password with the MariaDB image.
For the database initialization script, I was torn between using an entrypoint script or ConfigMaps.
Up until that point, I did not know that ConfigMaps can be created from files. I went with the ConfigMap method to get hands on with that process.

To create the configmap from the sql file

```bash
kubectl create configmap db-init-script --from-file=db-load-script.sql
```

# Setting Up Kubernetes Cluster

For my cluster, I went with AWS and [kOps](https://kops.sigs.k8s.io/).
Setting up a Kubernetes cluster on AWS is simplified with kOps. A few prerequisites need to be in place;

- a Route53 hosted zone
- an S3 bucket
- an iAM user and credentials with the following permissions;
  ```
  AmazonEC2FullAccess
  AmazonRoute53FullAccess
  AmazonS3FullAccess
  IAMFullAccess
  AmazonVPCFullAccess
  AmazonSQSFullAccess
  AmazonEventBridgeFullAccess
  ```
- AWS CLI installed and configured using the kOps iAM user credentials

With these prerequisites in place, create the cluser

```bash
export KOPS_STATE_STORE=s3://<bucket-name>

kops create cluster --name=<subdomain.domain.com> --state=s3://<bucket-name> --zones=us-east-1a,us-east-1b --node-count=1 --node-size=t3.small --control-plane-size=t3.small --dns-zone=<subdomain.domain.com>

kops update cluster --name=<subdomain.domain.com> --yes
```

## Configuring kubectl

For kubectl to work with the cluster, the following commands were run

```bash
kops export kubecfg --admin

kubectl get node
```

# Deploying the Application

After my cluster was setup, I proceeded to deploy the application and database. I started with the database and I wrote the following manifests for it;

- [database-service](https://github.com/Chxnedu/learning-app-ecommerce/blob/master/k8s-manifests/db/db-service.yaml); a simple database service of the default type ClusterIP. the database is only accessible from within the cluster
- [db-secrets](https://github.com/Chxnedu/learning-app-ecommerce/blob/master/k8s-manifests/db/db-secrets.yaml); a Secrets object to store secrets like passwords
- [db-pvc](https://github.com/Chxnedu/learning-app-ecommerce/blob/master/k8s-manifests/db/db-pvc.yaml); implemented persistent storage for the database to ensure data persistence across pod restarts and redeployments
- [db-configmap](https://github.com/Chxnedu/learning-app-ecommerce/blob/master/k8s-manifests/db/db-configmap.yaml); a ConfigMap to store the environment variables needed by the database
- [db-deployment](https://github.com/Chxnedu/learning-app-ecommerce/blob/master/k8s-manifests/db/db-deployment.yaml); the database deployment file specifying the image, replicas, volumes and other configurations.

I proceeded to write the following manifests for the application;

- [app-service](https://github.com/Chxnedu/learning-app-ecommerce/blob/master/k8s-manifests/application/app-service.yaml)
- [app-secrets](https://github.com/Chxnedu/learning-app-ecommerce/blob/master/k8s-manifests/application/app-secrets.yaml)
- [app-configmap](https://github.com/Chxnedu/learning-app-ecommerce/blob/master/k8s-manifests/application/app-configmap.yaml)
- [darkmode-configmap](https://github.com/Chxnedu/learning-app-ecommerce/blob/master/k8s-manifests/application/feature-configmap.yaml)
- [app-deployment](https://github.com/Chxnedu/learning-app-ecommerce/blob/master/k8s-manifests/application/app-deployment.yaml)

I deployed each object using

```bash
kubectl apply -f <file-name>.yaml
```

Where `file-name` is replaced by the name of the file.

## Challenges

The first challenge I ran into was my application not being able to connect to the database. I spent hours debugging and trying to find out a solution to my issue, but nothing was working. It seemed almost impossible to resolve this issue, and just as I was about to give up, I took one last look at my database service file and realized I used the wrong selector.

When your deployment is not working as it's supposed to, the first place to look should be your configuration files. Don't be like me that spent hours entering the pods and looking for solutions when the issue was so simple.
