terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {}
  skip_provider_registration = true
}

# Use an existing Resource Group
data "azurerm_resource_group" "rg" {
  name = "1-f37d2a3f-playground-sandbox"
}

# Existing Azure Container Registry
data "azurerm_container_registry" "acr" {
  name                = "f37d2a3fACR"
  resource_group_name = data.azurerm_resource_group.rg.name
}

# Kubernetes Cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aksCluster"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  dns_prefix          = "aks"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_DS2_v2"
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    dns_service_ip = "10.2.0.10"
    service_cidr   = "10.2.0.0/24"
    docker_bridge_cidr = "172.17.0.1/16"
  }


  } 


# Kubernetes Provider
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
}

# Namespace
resource "kubernetes_namespace" "example" {
  metadata {
    name = "example"
  }
}

# Deployment for MariaDB
resource "kubernetes_deployment" "mariadb" {
  metadata {
    name      = "mariadb"
    namespace = kubernetes_namespace.example.metadata[0].name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "mariadb"
      }
    }
    template {
      metadata {
        labels = {
          app = "mariadb"
        }
      }
      spec {
        container {
          image = "${data.azurerm_container_registry.acr.login_server}/mdbimage:latest"
          name  = "mariadb"
          env {
            name  = "MYSQL_ROOT_PASSWORD"
            value = "my-secret-pw"
          }
          port {
            container_port = 3306
          }
        }
      }
    }
  }
}

# Service for MariaDB
resource "kubernetes_service" "mariadb" {
  metadata {
    name      = "mariadb"
    namespace = kubernetes_namespace.example.metadata[0].name
  }
  spec {
    selector = {
      app = "mariadb"
    }
    port {
      port        = 3306
      target_port = 3306
    }
  }
}

# Deployment for WordPress
resource "kubernetes_deployment" "wordpress" {
  metadata {
    name      = "wordpress"
    namespace = kubernetes_namespace.example.metadata[0].name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "wordpress"
      }
    }
    template {
      metadata {
        labels = {
          app = "wordpress"
        }
      }
      spec {
        container {
          image = "${data.azurerm_container_registry.acr.login_server}/wpimage:latest"
          name  = "wordpress"
          env {
            name  = "WORDPRESS_DB_HOST"
            value = "mariadb"
          }
          env {
            name  = "WORDPRESS_DB_NAME"
            value = "wordpress"
          }
          env {
            name  = "WORDPRESS_DB_USER"
            value = "wp_user"
          }
          env {
            name  = "WORDPRESS_DB_PASSWORD"
            value = "wp_password"
          }
          port {
            container_port = 80
          }
        }
      }
    }
  }
}

# Service for WordPress
resource "kubernetes_service" "wordpress" {
  metadata {
    name      = "wordpress"
    namespace = kubernetes_namespace.example.metadata[0].name
  }
  spec {
    selector = {
      app = "wordpress"
    }
    port {
      port        = 80
      target_port = 80
    }
    type = "LoadBalancer"
  }
}
