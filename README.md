# Introduction

The Kubernetes Resume Challenge leverages Kubernetes and Containerization using Docker to deploy a PHP E-Commerce website. Docker encapsulates the application and its environment, ensuring it runs consistently everywhere, and Kubernetes automates deployment, scaling, and management of the application.

I took on this project after completing the [Certified Kubernetes Administrator Course](https://www.udemy.com/course/certified-kubernetes-administrator-with-practice-tests/?srsltid=AfmBOorl2NfsH0jy-wtTytR-OMwW40iBy9EXBB4acngtO32OodEM3ciT) from KodeKloud to test and validate my skills. This article details my approach to the challenge, the decisions I made, and all the new things I learned during this challenge.

The fully deployed site is available at https://k8s-challenge.chxnedu.xyz

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

The application uses a two-tier architecture; the client tier and the data tier (database). I built the application into an image using a Dockerfile, while the database uses the default MariaDB image.
I designed a Dockerfile for the application, following best practices.

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

You should build the image and test it locally to ensure it works before pushing it to Docker Hub.

```bash
docker build -t chxnedu/ecommerce-app:v1 .

docker push chxnedu/ecommerce-app:v1
```

## The Database

I configured environment variables to configure the database name, user and password with the MariaDB image.
For the database initialization script, I debated using an Entrypoint script versus ConfigMaps.
Up until that point, I did not know ConfigMaps could be created from files. I opted for the ConfigMap method to get hands on with that process.

I generated the ConfigMap from the SQL file by running

```bash
kubectl create configmap db-init-script --from-file=db-load-script.sql
```

---

# Setting Up Kubernetes Cluster

For my cluster, I went with AWS and [kOps](https://kops.sigs.k8s.io/).
Setting up a Kubernetes cluster on AWS is simplified with kOps. A few prerequisites need to be in place;

- Route53 hosted zone
- S3 bucket
- IAM user and credentials with the following permissions;
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

With these prerequisites in place, create the cluster

```bash
export KOPS_STATE_STORE=s3://<bucket-name>

kops create cluster --name=<subdomain.domain.com> --state=s3://<bucket-name> --zones=us-east-1a,us-east-1b --node-count=1 --node-size=t3.small --control-plane-size=t3.small --dns-zone=<subdomain.domain.com>

kops update cluster --name=<subdomain.domain.com> --yes
```

## Configuring kubectl

I ran the following commands to configure kubectl to work with the cluster

```bash
kops export kubecfg --admin

kubectl get node
```

---

# Deploying the Application

After my cluster was set up, I proceeded to deploy the application and database. I started with the database and wrote the following manifests for it;

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

Replace `file-name` with the actual file name.

## Managing Environment Variables and Secrets

I leveraged ConfigMaps and Secrets to manage environment variables for the database and application. I wrote a ConfigMap manifest

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: <configmap-name>
data:
  key: "value"
```

and a Secret manifest

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: <secret-name>
data:
  key: base64Value
```

## Exposing the Application

I exposed the application using a `LoadBalancer` Service. This Service type creates a Load balancer on AWS and outputs the URL which the application can be accessed on when `kubectl get service` is run. My issue with this implementation is that the load balancer was using HTTP and not HTTPS, so I had to change it.

After digging into how to enable SSL termination on my application, I discovered how `annotations` can be used to connect an AWS Certificate Manager (ACM) Certificate to a Kubernetes LoadBalancer Service. To enable this, you need to have a domain with an ACM Certificate, and include the following annotations in your Service manifest;

```yaml
annotations:
  # the backend talks over HTTP
  service.beta.kubernetes.io/aws-load-balancer-backend-protocol: http
  # use the arn of your certificate
  service.beta.kubernetes.io/aws-load-balancer-ssl-cert: arn:aws:acm:{region}:{user-id}:certificate/{id}
  # https port
  service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "443"
```

## Challenges

The biggest challenge I faced was that my application couldn't connect to the database. I spent hours debugging and troubleshooting to find out a solution to my issue, but nothing was working. Resolving this issue seemed almost impossible, and just as I was about to give up, I took one last look at my database service file and realized I had used the wrong selector.
When your deployment is not working as it's supposed to, avoid spending hours inside pods searching for fixes when the answer is in your configuration files. Always check the files first.

---

# Implementing Scalability and Reliability

I implemented Horizontal Pod Autoscaler (HPA), liveness and readiness probes, and rolling updates to ensure the application scales with traffic and remains available during updates.

## Configuring HPA for Scaling

I implemented an HPA that targets 50% CPU utilization, with a minimum of 2 and a maximum of 5 pods using this command

```bash
kubectl autoscale deployment app --cpu-percent=50 --min=2 --max=10
kubectl get hpa # to monitor the autoscaling
```

## Setting up Liveness and Readiness probes

I implemented liveness and readiness probes in the deployment manifest to monitor pod health.

```yaml
livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 3
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
```

## Rolling Updates for Zero-Downtime

I updated the application image and changed the deploment manifest to include the new image version. To apply the changes;

```bash
kubectl apply -f app-deployment.yaml

# to monitor the rolling update process
kubectl rollout status deployment/app
```

The pods terminate and restart sequentially, rather than all at once. This ensures your application is always available.

---

# Automating Deployment with CI/CD

---

# Conclusion and Next Steps

Through this project, I deployed a sample e-commerce application and database to a live Kubernetes environment, utilizing various Kubernetes objects and concepts like PersistentVolumes, ConfigMaps, Secrets, HPA, and Probes.

This challenge significantly strengthened my experience in setting up Kubernetes clusters, deploying and managing applications on Kubernetes, and imlementing scalability and reliability.

I plan to make the following enhancements to this project going forward;

- Helm Packaging
- Utilizing Vault for managing secrets
