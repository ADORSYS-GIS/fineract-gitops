# ArgoCD ApplicationSets

This document explains the use of ArgoCD `ApplicationSets` to manage and automate the creation of ArgoCD `Application` resources across multiple environments.

## Overview

The `ApplicationSet` controller is a powerful feature of ArgoCD that allows you to create and manage multiple ArgoCD applications from a single, declarative resource. This approach reduces boilerplate, ensures consistency across environments, and simplifies the process of adding new applications or environments.

In this project, we use an `ApplicationSet` to generate the `fineract` application for the `dev`, `uat`, and `prod` environments.

## The `fineract-applicationset.yaml` File

The `argocd/applications/fineract-applicationset.yaml` file defines the `ApplicationSet` for the Fineract core banking application.

### Generators

The `generators` section defines the parameters for each environment. We use a "list" generator to specify the environment-specific values:

```yaml
generators:
- list:
    elements:
    - environment: dev
      targetRevision: develop
      project: fineract-dev
    - environment: uat
      targetRevision: main
      project: fineract-uat
    - environment: prod
      targetRevision: main
      project: fineract-production
```

Each element in this list corresponds to an environment and defines:
*   `environment`: The name of the environment (e.g., `dev`, `uat`, `prod`).
*   `targetRevision`: The Git branch to sync from.
*   `project`: The ArgoCD project to associate the application with.

### Template

The `template` section defines the structure of the ArgoCD `Application` resources that will be generated. It uses placeholders (e.g., `{{environment}}`, `{{project}}`) that are replaced with the values from the generator.

```yaml
template:
  metadata:
    name: 'fineract-{{environment}}-fineract'
    # ...
  spec:
    project: '{{project}}'
    source:
      repoURL: https://github.com/ADORSYS-GIS/fineract-gitops.git
      targetRevision: '{{targetRevision}}'
      path: 'environments/{{environment}}'
    destination:
      server: https://kubernetes.default.svc
      namespace: 'fineract-{{environment}}'
    # ...
```

## How to Transition to ApplicationSets

To transition from the individual `fineract.yaml` files to the new `ApplicationSet`, you would perform the following steps:

1.  **Apply the `ApplicationSet`**:
    ```bash
    kubectl apply -f argocd/applications/fineract-applicationset.yaml
    ```
    This will create the `ApplicationSet` resource in the `argocd` namespace. The `ApplicationSet` controller will then automatically generate the `fineract-dev-fineract`, `fineract-uat-fineract`, and `fineract-prod-fineract` ArgoCD `Application` resources.

2.  **Delete the Old Application Definitions**:
    Once you have verified that the new applications have been created and are syncing correctly, you can safely delete the old, individual `fineract.yaml` files from the `argocd/applications/dev/`, `argocd/applications/uat/`, and `argocd/applications/prod/` directories.

    ```bash
    git rm argocd/applications/dev/fineract.yaml
    git rm argocd/applications/uat/fineract.yaml
    git rm argocd/applications/prod/fineract.yaml
    git commit -m "refactor: Replace individual Fineract applications with ApplicationSet"
    git push
    ```

## Adding New Applications or Environments

### Adding a New Application

To manage another application (e.g., `keycloak`) with an `ApplicationSet`, you would create a new `keycloak-applicationset.yaml` file with a similar structure, defining the appropriate generator and template for the `keycloak` application.

### Adding a New Environment

To add a new environment (e.g., `staging`), you would simply add a new element to the `generators.list.elements` section in the `fineract-applicationset.yaml` file:

```yaml
- environment: staging
  targetRevision: main
  project: fineract-staging
```

The `ApplicationSet` controller will automatically generate a new `fineract-staging-fineract` application for the new environment.
