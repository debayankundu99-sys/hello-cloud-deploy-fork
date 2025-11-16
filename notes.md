# Class starts 09:05 AM

### CI CD

#### CI - Continuous Integration

- Build source code
- Running tests
- Scanning Code ( for source code quality ) [Static Code Analysis]
- Security Scanning ( security threats )
- Package Code ( docker contaier, war, zip etc.,)
- Push Code into Artifact / Container registry
- Deploy Code into Cloud Run

#### GCP Services

- Cloud build - Serverless build systems
  - yaml file as configuration - which we term as build pipeline
  - steps - which uses cloud builders ( npm, bazel, mvn, dotnet, gradle, docker, cloud-sdk)
- Container Registry - This hosts docker conatiners

# CD - Continuous Delivery

`Continuous Delivery automates the process of getting code from “ready” to “ready for deployment.”`

- Packages the application
- Stores the artifacts
- Deploys to non-prod environments (dev, QA, staging)
- Prepares everything required to deploy to production
- But deployment to production is a **manual approval** step

#### Key goals of Continuous Delivery

- Reduce manual steps
- Ensure deployments are reliable
- Deploy any time with confidence
- Release small, frequent updates
- Detect issues early in lower environments

#### Example Workflow:

You commit code → Pipeline builds, tests, packages → Deploys automatically to DEV & QA → waits for manual approval → can deploy to PROD anytime.

# GCP Cloud Deploy

## What is Cloud Deploy?

- Fully managed continuous delivery (CD) service on Google Cloud.
- Automates promotions of application releases across multiple environments (dev → qa → prod).
- Works best with Cloud Build, Artifact Registry, **Cloud Run**, GKE, and Cloud Functions.

## Why Cloud Deploy?

- Single declarative config controlling the entire delivery pipeline.
- Built-in **rollbacks**, **approvals**, **verifications**, **audit logs**.
- Eliminates custom scripts for promotions.
- Consistent delivery model across microservices.

## Key Concepts

- Delivery Pipeline: Defines the **sequence of environments** and how releases move across them.`
- Target:
  - An environment to deploy into (dev, qa, staging, prod).
  - Each target points to:
    - A GKE cluster, Cloud Run region, or Cloud Functions location.
    - Optional **approval** requirement before promotion.
- Release:
  - A snapshot of the artifacts + pipeline version.
- Rollout:
  - A deployment of a release to a target.
  - Rollouts contain phases + steps.
  - Can be monitored and paused/resumed.
- Approvals:
  - Can enforce a human-in-loop approval before deploying to prod.

# Dependencies

- We need to deploy a service
  - I need a binary ( docker )
    - By building docker container
      - Push this container to registry
- I have a binary - where should I run this binary?
  - I want to run the binary in cloud run
    - Tell me the settings you need - Please give the configuration in yaml ( k8s/cloudrun-service-dev.yaml )

# Steps to CD

- I need to build => Using cloud build => It uses configuration => cloudbuild.yaml
- cloudbuild.yaml
  - Step 0: npm ci
  - Step 1: npm test
  - Step 2: build image
  - Step 3: push image - next step?
  - Step 4: create a release => How do I know about environment? A: Use delivery pipeline, which delivery pipeline? = order-api-pipeline
