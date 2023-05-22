---
title: Pipeline automation - Zero downtime AKS upgrades
published: false
description: Tech Flake 002 - Pipeline automation - Zero downtime AKS upgrades
tags: 'aks, azure pipelines, rancher, powershell, k8s'
cover_image: ./assets/001-birds.jpg
canonical_url: null
date: ''
id: 
---

Upgrading an AKS cluster can sometimes be a major footgun. There are several reasons why an upgrade of your cluster could fail. Achieving zero downtime on your cluster upgrades requires careful planning specific to your design implementation. A few years back, when me and my team started out with Kubernetes / AKS, we followed the manual approach of upgrading the cluster in a sequential manner basing the steps outlined below

- Upgrade the AKS control plane.
- Add temporary buffer nodes.
- Cordon the original nodes.
- Restart all user deployments so that the pods are moved to temporary nodes.
- Drain the original nodes.
- Upgrade the original nodes.
- Cordon the buffer nodes.
- Restart all user deployments so that the pods move back to original nodes.
- Drain the buffer nodes.
- Delete the buffer nodes.

This workflow was an outcome of reading this post and it helped avoid downtime for our applications whilst performing the cluster upgrades as we had better control over the upgrade process all the way. We did not want to use the az aks upgrade command for the upgrades as this was noted to fail twice during our pilot tests in acceptance. There was the feeling of not being in control with this approach. Also back then while we were still on k8s version 1.18, our windows containerized workloads were very bulky with container images over 6Gi in size. This resulted in substantial downtime for our applications when upgrades failed midway as images had to be downloaded newly before the containers could be instantiated during the upgrade process. Automatic upgrade was obviously something that we did not want to implement in our setup for similar reasons too. As I previously remarked, there are many reasons that could result in a cluster ugrade failure. Some of these in our case have been listed below

- deleted Azure Container Registry (ACR) images for user deployments, applications in k8s.
- known node drain failure limitation when having a single pod replica in a deployment with Pod Disruption Budget (pdb) configuration.
- deprecated APIs for workloads that were not tested before the upgrade.
- compatibility issues. The new version of AKS may introduce changes that are not compatible with your existing workloads, applications, or configurations. 

Over time, the number of AKS clusters that had to be managed grew in number and we started looking at ways to automate the entire upgrade workflow. PowerShell was our tool of choice in this quest. The initial versions of our upgrade script used native kubectl commands alongside the powershell Az Aks commands. This was very clunky as the script execution was dependent on the local kubeconfig profile configuration that has been used for managing the kubernetes clusters. We also had security implications when reviewing the possibilities of running the script on self-hosted azure devops agents with azure pipelines. Changing the cluster context was not allowed while running the script locally. Accidentally changing your k8s cluster context during the script run was dangerous as this led to unitended AKS clusters being cordoned, drained etc. A smarter workflow had to be thought of.

We had a solution to our woes in Rancher. If you have not checked out Rancher, I suggest to have a look here. It is an open source software and provides a central platform for management of all your k8s clusters (AKS, k3s, etc.). There are a plenty of benefits for managing kubernetes using Rancher. Some of them in our case have been listed below

- Rancher APIs can be used for automating all kubernetes actions possible with kubectl by querying against a single URL. This enabled us to build PowerShell functions for kubectl actions by leveraging REST commands. Our setup includes 2 Rancher instances to manage acceptance and production environments individually.
Rancher environment could be isolated to the office network IP ranges and this would enable secure accessibility for Rancher UI and API.
- Rancher integrates well with Azure AD. This eased RBAC management within kubernetes. Access could be granted to the developer teams with custom access permissions without having to worry about the security risk with kubeconfig files.
- Rancher provides an integrated shell which could be used for running kubectl commands for troubleshooting.
- 