# CI/CD with Google Cloud Platform - Class Notes

## Course Overview

This course teaches students how to build an enterprise-grade CI/CD (Continuous Integration/Continuous Deployment) pipeline using Google Cloud Platform services. Students will learn to automate the entire software delivery process from code commit to production deployment.

**Duration**: 4-6 hours  
**Level**: Intermediate  
**Prerequisites**: Basic understanding of Git, Docker, and cloud computing concepts

---

## Table of Contents

1. [Learning Objectives](#learning-objectives)
2. [Core Concepts](#core-concepts)
3. [Architecture Overview](#architecture-overview)
4. [GCP Services Deep Dive](#gcp-services-deep-dive)
5. [Project Structure](#project-structure)
6. [Implementation Guide](#implementation-guide)
7. [Best Practices](#best-practices)
8. [Common Pitfalls](#common-pitfalls)
9. [Assessment Questions](#assessment-questions)
10. [Further Learning](#further-learning)

---

## Learning Objectives

By the end of this course, students will be able to:

✅ Explain the concepts and benefits of CI/CD pipelines  
✅ Understand GCP's cloud-native services for application deployment  
✅ Design and implement a multi-environment deployment strategy  
✅ Configure automated testing and building with Cloud Build  
✅ Set up progressive delivery pipelines with Cloud Deploy  
✅ Deploy serverless containers to Cloud Run  
✅ Implement proper IAM (Identity and Access Management) for service accounts  
✅ Troubleshoot common CI/CD pipeline issues

---

## Core Concepts

### What is CI/CD?

**CI/CD** stands for **Continuous Integration** and **Continuous Deployment/Delivery**.

#### Continuous Integration (CI)

**What**: Automatically building and testing code whenever changes are committed  
**Why**: Catch bugs early, ensure code quality, reduce integration problems  
**How**: Automated build + automated tests run on every commit

**Example Flow**:

```
Developer commits code → Build triggers → Code compiled → Tests run → Report results
```

#### Continuous Deployment (CD)

**What**: Automatically deploying tested code to production environments  
**Why**: Faster releases, reduced manual errors, consistent deployments  
**How**: Automated deployment pipeline with approval gates

**Example Flow**:

```
Tests pass → Deploy to Dev → Deploy to Staging → Approval → Deploy to Production
```

### Why Use CI/CD?

| Traditional Deployment | With CI/CD                    |
| ---------------------- | ----------------------------- |
| Manual builds          | Automated builds              |
| Days/weeks to deploy   | Minutes to deploy             |
| High risk of errors    | Consistent, repeatable        |
| Limited testing        | Comprehensive automated tests |
| Fear of deployment     | Confidence in deployment      |

---

## Architecture Overview

### High-Level Architecture

```
┌─────────────┐         ┌──────────────┐         ┌─────────────┐
│   GitHub    │  Push   │ Cloud Build  │  Image  │  Artifact   │
│ Repository  ├────────>│   (CI)       ├────────>│  Registry   │
└─────────────┘         └──────┬───────┘         └─────────────┘
                               │ Release
                               ↓
                        ┌──────────────┐
                        │ Cloud Deploy │
                        │   (CD)       │
                        └──────┬───────┘
                               │
                ┌──────────────┼──────────────┐
                ↓              ↓              ↓
         ┌──────────┐   ┌──────────┐   ┌──────────┐
         │Cloud Run │   │Cloud Run │   │Cloud Run │
         │   Dev    │   │ Staging  │   │  Prod    │
         └──────────┘   └──────────┘   └──────────┘
```

### Component Responsibilities

| Component             | Role               | Why It Matters                         |
| --------------------- | ------------------ | -------------------------------------- |
| **GitHub**            | Source control     | Single source of truth for code        |
| **Cloud Build**       | CI - Build & Test  | Ensures code quality before deployment |
| **Artifact Registry** | Container storage  | Versioned, secure image storage        |
| **Cloud Deploy**      | CD - Orchestration | Manages multi-environment deployments  |
| **Cloud Run**         | Runtime platform   | Serverless container execution         |

---

## GCP Services Deep Dive

### 1. Cloud Build

**What**: Fully managed CI/CD platform for building, testing, and deploying code

**Why Use It**:

- ✅ No infrastructure to manage
- ✅ Pay only for build time
- ✅ Integrated with GCP services
- ✅ Supports Docker, npm, Maven, etc.

**How It Works**:

1. Trigger listens for GitHub commits
2. Reads `cloudbuild.yaml` configuration
3. Executes build steps in isolated containers
4. Each step can use different base images
5. Results stored and logged

**Key Concepts**:

#### Build Steps

Each step runs in a container:

```yaml
steps:
  - name: "node:18-alpine" # Container image to use
    id: "install-deps" # Unique identifier
    entrypoint: "npm" # Command to run
    args: ["ci"] # Arguments
```

**Why separate steps?**

- Each step is isolated
- Can use different environments
- Easy to debug failures
- Steps can run in parallel

#### Substitutions

Variables passed to builds:

```yaml
substitutions:
  _SERVICE_NAME: "order-api"
  _REGION: "asia-south1"
```

**Why use substitutions?**

- Reusable configurations
- Different values per trigger
- No hardcoded values

#### Built-in Variables

Cloud Build provides automatic variables:

- `${PROJECT_ID}` - Your GCP project
- `${BUILD_ID}` - Unique build identifier
- `${SHORT_SHA}` - Git commit hash (short)
- `${BRANCH_NAME}` - Git branch

**Real-World Example**:

```yaml
# Step 1: Install dependencies
- name: "node:18-alpine"
  id: "install-deps"
  entrypoint: "npm"
  args: ["ci"]

# Step 2: Run tests
- name: "node:18-alpine"
  id: "run-tests"
  entrypoint: "npm"
  args: ["test"]
  waitFor: ["install-deps"] # Wait for dependencies first

# Step 3: Build Docker image
- name: "gcr.io/cloud-builders/docker"
  id: "build-image"
  args:
    [
      "build",
      "-t",
      "asia-south1-docker.pkg.dev/${PROJECT_ID}/order-api-repo/order-api:${BUILD_ID}",
      ".",
    ]
  waitFor: ["run-tests"] # Only build if tests pass
```

---

### 2. Artifact Registry

**What**: Secure, private container registry for storing Docker images

**Why Use It** (vs. Docker Hub):

- ✅ Private by default
- ✅ Fine-grained IAM permissions
- ✅ Integrated with GCP
- ✅ Vulnerability scanning
- ✅ Regional storage (low latency)

**How It Works**:

1. Create a repository (one-time setup)
2. Build images with proper tags
3. Push images to registry
4. Pull images for deployment

**Image Naming Convention**:

```
LOCATION-docker.pkg.dev/PROJECT-ID/REPOSITORY/IMAGE:TAG
asia-south1-docker.pkg.dev/my-project/order-api-repo/order-api:v1.0.0
```

**Why this format?**

- `LOCATION`: Regional storage for faster pulls
- `PROJECT-ID`: Namespace isolation
- `REPOSITORY`: Logical grouping of images
- `IMAGE`: Service name
- `TAG`: Version identifier

**Best Practices**:

- ✅ Use semantic versioning (v1.0.0)
- ✅ Tag with commit SHA for traceability
- ✅ Keep dev/staging/prod images separate
- ✅ Clean up old images regularly

---

### 3. Cloud Deploy

**What**: Managed continuous delivery service for multi-environment deployments

**Why Use It**:

- ✅ Progressive delivery (dev → staging → prod)
- ✅ Approval workflows
- ✅ Rollback capabilities
- ✅ Audit trail of all deployments
- ✅ Skaffold integration

**Key Concepts**:

#### Delivery Pipeline

A sequence of stages for software delivery:

```yaml
serialPipeline:
  stages:
    - targetId: order-api-dev # Stage 1: Dev
      profiles: [dev]
    - targetId: order-api-staging # Stage 2: Staging
      profiles: [staging]
    - targetId: order-api-prod # Stage 3: Production
      profiles: [prod]
```

**Why stages?**

- Test in dev first
- Validate in staging
- Minimize production risk

#### Targets

Where to deploy (dev, staging, prod):

```yaml
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: order-api-dev
run:
  location: projects/PROJECT_ID/locations/REGION
```

**Why separate targets?**

- Different configurations per environment
- Independent scaling
- Isolated testing

#### Releases

A specific version ready for deployment:

```bash
gcloud deploy releases create release-v1.0.0 \
  --delivery-pipeline=order-api-pipeline \
  --images=order-api=asia-south1-docker.pkg.dev/...
```

**Release = Immutable artifact + Configuration**

#### Rollouts

Actual deployment to a target:

```
Release created → Rollout to dev → Rollout to staging → Rollout to prod
```

**Each rollout is tracked and can be rolled back**

---

### 4. Cloud Run

**What**: Fully managed serverless platform for running containers

**Why Use It**:

- ✅ **Serverless**: No server management
- ✅ **Auto-scaling**: Scales to zero (no cost when idle)
- ✅ **Pay per use**: Only pay for request time
- ✅ **Any language**: Run any containerized app
- ✅ **Fast deployment**: Deploy in seconds

**How It Works**:

1. Upload container image
2. Cloud Run creates service
3. Automatically assigns HTTPS endpoint
4. Scales instances based on traffic
5. Scales to zero when no traffic

**Key Concepts**:

#### Container Requirements

Your container must:

- ✅ Listen on port defined by `$PORT` environment variable
- ✅ Start within 4 minutes
- ✅ Respond to HTTP requests
- ✅ Be stateless (no local file storage)

**Example (Node.js)**:

```javascript
const PORT = process.env.PORT || 8080; // Cloud Run sets PORT
app.listen(PORT, "0.0.0.0", () => {
  console.log(`Server running on port ${PORT}`);
});
```

#### Revisions

Each deployment creates a new revision:

```
Service: order-api-dev
├── Revision: order-api-dev-00001 (50% traffic)
└── Revision: order-api-dev-00002 (50% traffic)
```

**Why revisions matter**:

- Gradual rollouts (traffic splitting)
- Easy rollback (shift traffic back)
- A/B testing capabilities

#### Autoscaling Configuration

```yaml
annotations:
  autoscaling.knative.dev/minScale: "1" # Minimum instances
  autoscaling.knative.dev/maxScale: "10" # Maximum instances
```

**Why configure scaling?**

- `minScale: 1` - Avoid cold starts (but costs more)
- `minScale: 0` - Save money (but slower first request)
- `maxScale: 10` - Prevent runaway costs

---

### 5. Skaffold

**What**: Tool for managing Kubernetes/Cloud Run configurations across environments

**Why Use It**:

- ✅ Environment-specific configurations (dev vs prod)
- ✅ Eliminates manual YAML editing
- ✅ Works with Cloud Deploy
- ✅ Local development support

**How It Works**:

```yaml
profiles:
  - name: dev
    manifests:
      rawYaml:
        - k8s/cloudrun-service-dev.yaml

  - name: prod
    manifests:
      rawYaml:
        - k8s/cloudrun-service-prod.yaml
```

**Cloud Deploy uses profiles to deploy different configs per environment**

---

## Project Structure

### File Organization

```
hello-cloud-deploy/
├── src/                          # Application code
│   ├── server.js                 # Express server
│   ├── routes/
│   │   ├── health.js             # Health check endpoint
│   │   └── orders.js             # Business logic
│   └── __tests__/                # Unit tests
│       └── server.test.js
├── k8s/                          # Kubernetes/Cloud Run manifests
│   ├── cloudrun-service-dev.yaml     # Dev environment
│   ├── cloudrun-service-staging.yaml # Staging environment
│   └── cloudrun-service-prod.yaml    # Production environment
├── cloudbuild.yaml               # CI configuration
├── clouddeploy.yaml              # CD pipeline configuration
├── skaffold.yaml                 # Deployment orchestration
├── Dockerfile                    # Container definition
├── package.json                  # Node.js dependencies
├── setup.sh                      # Automated setup script
├── cleanup.sh                    # Resource cleanup script
└── commands.md                   # Manual setup guide
```

### Why This Structure?

| Directory/File  | Purpose                | Why Separate?                 |
| --------------- | ---------------------- | ----------------------------- |
| `src/`          | Application code       | Separation of concerns        |
| `k8s/`          | Infrastructure configs | Environment-specific settings |
| Root YAML files | CI/CD configs          | Pipeline definitions          |
| Scripts         | Automation             | Reusable setup/teardown       |

---

## Implementation Guide

### Module 1: Understanding the Application

#### What We're Building

A simple Order API microservice with:

- Health check endpoint (`GET /health`)
- Create order endpoint (`POST /orders`)
- Input validation
- Error handling
- Environment awareness

#### Code Walkthrough

**1. Server Setup (`src/server.js`)**

```javascript
const PORT = process.env.PORT || 8080;
const SERVICE_ENV = process.env.SERVICE_ENV || "local";
```

**Why read environment variables?**

- `PORT`: Cloud Run sets this automatically
- `SERVICE_ENV`: Know which environment we're in (dev/staging/prod)

```javascript
if (require.main === module) {
  app.listen(PORT, "0.0.0.0", () => {
    console.log(`Server running on port ${PORT}`);
  });
}

module.exports = app;
```

**Why this pattern?**

- Allows testing without starting server
- Jest can import without side effects
- Production runs normally

**2. Health Check (`src/routes/health.js`)**

```javascript
router.get("/", (req, res) => {
  res.status(200).json({
    status: "healthy",
    timestamp: new Date().toISOString(),
    environment: process.env.SERVICE_ENV || "unknown",
  });
});
```

**Why health checks?**

- Cloud Run uses them to verify service is ready
- Load balancers use them for routing decisions
- Monitoring systems use them for alerting

**3. Order Validation (`src/routes/orders.js`)**

```javascript
router.post(
  "/",
  [
    body("customerId").notEmpty().withMessage("Customer ID is required"),
    body("items").isArray({ min: 1 }).withMessage("At least one item required"),
    body("totalAmount")
      .isFloat({ min: 0 })
      .withMessage("Total amount must be positive"),
  ],
  createOrder
);
```

**Why validate input?**

- Security: Prevent bad data
- User experience: Clear error messages
- Data integrity: Consistent database state

---

### Module 2: Containerization

#### Understanding the Dockerfile

```dockerfile
# Stage 1: Build stage
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
```

**Why multi-stage build?**

- Smaller final image (exclude dev dependencies)
- Faster builds (cache layers)
- More secure (only production code)

```dockerfile
# Stage 2: Production stage
FROM node:18-alpine
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/src ./src
COPY --from=builder /app/package*.json ./
```

**Why copy from builder?**

- Only production files in final image
- Reduces image size by 50%+
- Improves security posture

```dockerfile
USER node
```

**Why non-root user?**

- Security best practice
- Limit attack surface
- Required by many security policies

```dockerfile
ENV NODE_ENV=production
EXPOSE 8080
CMD ["node", "src/server.js"]
```

**Why these settings?**

- `NODE_ENV=production`: Optimized performance
- `EXPOSE 8080`: Documentation (Cloud Run uses $PORT)
- `CMD`: Default command to run

#### .dockerignore

```
node_modules/
.git/
*.md
.env
```

**Why exclude these?**

- Faster builds (less data to copy)
- Smaller images
- Don't leak sensitive files

---

### Module 3: CI Pipeline (Cloud Build)

#### cloudbuild.yaml Breakdown

**Step 1: Install Dependencies**

```yaml
- name: "node:18-alpine"
  id: "install-deps"
  entrypoint: "npm"
  args: ["ci"]
```

**Why `npm ci` instead of `npm install`?**

- ✅ Faster (skips package resolution)
- ✅ Consistent (uses package-lock.json exactly)
- ✅ Better for CI/CD (fails if lock file is out of sync)

**Step 2: Run Tests**

```yaml
- name: "node:18-alpine"
  id: "run-tests"
  entrypoint: "npm"
  args: ["test"]
  waitFor: ["install-deps"]
```

**Why test before building?**

- ❌ If tests fail → Stop pipeline (save time and money)
- ✅ If tests pass → Continue to build

**Step 3: Build Docker Image**

```yaml
- name: "gcr.io/cloud-builders/docker"
  id: "build-image"
  args:
    [
      "build",
      "-t",
      "${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO_NAME}/${_SERVICE_NAME}:${BUILD_ID}",
      ".",
    ]
  waitFor: ["run-tests"]
```

**Why use BUILD_ID as tag?**

- ✅ Unique for every build
- ✅ Traceable to specific commit
- ✅ Easy to identify in Artifact Registry

**Step 4: Push to Artifact Registry**

```yaml
- name: "gcr.io/cloud-builders/docker"
  id: "push-image"
  args:
    [
      "push",
      "${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO_NAME}/${_SERVICE_NAME}:${BUILD_ID}",
    ]
  waitFor: ["build-image"]
```

**Step 5: Create Cloud Deploy Release**

```yaml
- name: "gcr.io/google.com/cloudsdktool/cloud-sdk"
  id: "create-release"
  entrypoint: "bash"
  args:
    - "-c"
    - |
      RELEASE_ID=$(date +%Y%m%d-%H%M%S)
      gcloud deploy releases create "${_SERVICE_NAME}-rel-$$RELEASE_ID" \
        --delivery-pipeline=${_SERVICE_NAME}-pipeline \
        --region=${_REGION} \
        --images=${_SERVICE_NAME}=${_REGION}-docker.pkg.dev/...
```

**Why generate release ID with timestamp?**

- ✅ Human-readable (know when it was created)
- ✅ Sortable chronologically
- ✅ Unique (includes timestamp to second)

---

### Module 4: CD Pipeline (Cloud Deploy)

#### clouddeploy.yaml Breakdown

**Delivery Pipeline**

```yaml
apiVersion: deploy.cloud.google.com/v1
kind: DeliveryPipeline
metadata:
  name: order-api-pipeline
description: Order API delivery pipeline for dev, staging, and production
serialPipeline:
  stages:
    - targetId: order-api-dev
      profiles: [dev]
    - targetId: order-api-staging
      profiles: [staging]
    - targetId: order-api-prod
      profiles: [prod]
```

**Why serial pipeline?**

- Must pass dev before staging
- Must pass staging before prod
- Reduces production risk

**Targets**

```yaml
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: order-api-prod
description: Production environment for Order API
requireApproval: true
run:
  location: projects/PROJECT_ID/locations/REGION
```

**Why require approval for prod?**

- Human verification step
- Compliance requirement
- Last chance to catch issues

---

### Module 5: Cloud Run Configuration

#### Understanding the Manifest

**Service Metadata**

```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: order-api-dev
  annotations:
    run.googleapis.com/ingress: all
```

**Why `ingress: all`?**

- Allows public internet access
- For internal services, use `internal`
- For load balancer only, use `internal-and-cloud-load-balancing`

**Revision Template**

```yaml
spec:
  template:
    metadata:
      annotations:
        run.googleapis.com/execution-environment: gen2
        autoscaling.knative.dev/minScale: "1"
        autoscaling.knative.dev/maxScale: "10"
```

**Gen1 vs Gen2?**

- Gen2: Newer, faster, better performance
- Gen2: More CPU/memory options
- Gen2: Recommended for new services

**Container Spec**

```yaml
spec:
  containerConcurrency: 80
  timeoutSeconds: 300
  containers:
    - image: order-api
      ports:
        - containerPort: 8080
      env:
        - name: SERVICE_ENV
          value: "dev"
```

**Why containerConcurrency: 80?**

- Number of concurrent requests per instance
- Too high: Instance overload
- Too low: Unnecessary scaling costs
- 80 is a good default for most apps

**Why timeoutSeconds: 300?**

- Maximum request duration (5 minutes)
- Prevents hanging requests
- For APIs, 30-60 seconds is usually enough

**Resources**

```yaml
resources:
  limits:
    cpu: "2"
    memory: 2Gi
  requests:
    cpu: "1"
    memory: 1Gi
```

**Limits vs Requests?**

- **Requests**: Guaranteed resources
- **Limits**: Maximum allowed
- Instance will throttle if hitting limits

**Traffic Management**

```yaml
traffic:
  - percent: 100
    latestRevision: true
```

**Why traffic splitting?**

- Gradual rollouts (canary deployments)
- A/B testing
- Safe rollbacks

---

### Module 6: IAM and Security

#### Service Accounts

**What**: Identity for services (not humans)

**Application Service Account**

```bash
gcloud iam service-accounts create order-api-sa \
  --display-name="Order API Service Account"
```

**Permissions Needed**:

- `roles/logging.logWriter` - Write logs
- `roles/cloudtrace.agent` - Send traces
- `roles/monitoring.metricWriter` - Send metrics

**Why separate service account?**

- Principle of least privilege
- Audit trail
- Easy to revoke access

**Cloud Build Service Account**

```bash
PROJECT_ID@cloudbuild.gserviceaccount.com
```

**Permissions Needed**:

- `roles/artifactregistry.writer` - Push images
- `roles/run.admin` - Deploy to Cloud Run
- `roles/clouddeploy.releaser` - Create releases
- `roles/iam.serviceAccountUser` - Act as service account

**Cloud Deploy Service Agent**

```bash
service-PROJECT_NUMBER@gcp-sa-clouddeploy.iam.gserviceaccount.com
```

**Permissions Needed**:

- `roles/iam.serviceAccountUser` - Act as app service account
- `roles/run.developer` - Deploy Cloud Run services

**Why so many permissions?**

- Cloud Build: Builds and creates releases
- Cloud Deploy: Deploys to Cloud Run
- Each needs specific permissions for their job

---

## Best Practices

### 1. Version Control

✅ **DO**:

- Commit cloudbuild.yaml, clouddeploy.yaml, Dockerfile
- Use meaningful commit messages
- Tag releases with semantic versioning

❌ **DON'T**:

- Commit secrets or credentials
- Commit node_modules or build artifacts
- Skip version control for config files

### 2. Testing

✅ **DO**:

- Write unit tests for all endpoints
- Test in dev environment first
- Set up automated testing in CI

❌ **DON'T**:

- Deploy untested code
- Skip validation testing
- Test directly in production

### 3. Environment Management

✅ **DO**:

- Use environment-specific configs
- Keep dev/staging similar to prod
- Use substitutions for variables

❌ **DON'T**:

- Hardcode project IDs or regions
- Use same config for all environments
- Skip staging environment

### 4. Security

✅ **DO**:

- Use service accounts with minimal permissions
- Keep secrets in Secret Manager
- Enable vulnerability scanning
- Use private Artifact Registry

❌ **DON'T**:

- Use default compute service account
- Store secrets in environment variables
- Make registries public
- Run containers as root

### 5. Monitoring

✅ **DO**:

- Implement health checks
- Monitor error rates
- Set up alerting
- Track deployment metrics

❌ **DON'T**:

- Deploy without monitoring
- Ignore failed health checks
- Skip log aggregation

### 6. Cost Optimization

✅ **DO**:

- Use minScale: 0 for dev/staging
- Clean up old images
- Monitor build minutes
- Use appropriate resource limits

❌ **DON'T**:

- Leave minScale: 1 for all services
- Keep all old images forever
- Over-provision resources

---

## Common Pitfalls

### Pitfall 1: PORT Environment Variable

**Problem**:

```yaml
env:
  - name: PORT
    value: "8080"
```

**Error**:

```
Error 400: The following reserved env names were provided: PORT
```

**Why This Happens**:
Cloud Run automatically sets `PORT` - you cannot override it.

**Solution**:

```javascript
// In your code:
const PORT = process.env.PORT || 8080;
```

Remove PORT from manifest - Cloud Run provides it.

---

### Pitfall 2: Service Account Permissions

**Problem**:

```
Permission 'iam.serviceaccounts.actAs' denied
```

**Why This Happens**:
Cloud Deploy needs permission to deploy using your service account.

**Solution**:

```bash
gcloud iam service-accounts add-iam-policy-binding \
    order-api-sa@PROJECT_ID.iam.gserviceaccount.com \
    --member="serviceAccount:service-PROJECT_NUMBER@gcp-sa-clouddeploy.iam.gserviceaccount.com" \
    --role="roles/iam.serviceAccountUser"
```

---

### Pitfall 3: Annotation Placement

**Problem**:

```yaml
metadata:
  annotations:
    run.googleapis.com/execution-environment: gen2 # ❌ Wrong place
```

**Error**:

```
Annotation 'run.googleapis.com/execution-environment' is not supported on Service
```

**Why This Happens**:
Some annotations belong on the Revision, not the Service.

**Solution**:

```yaml
spec:
  template:
    metadata:
      annotations:
        run.googleapis.com/execution-environment: gen2 # ✅ Correct
```

---

### Pitfall 4: GitHub Repository Not Connected

**Problem**:

```
ERROR: INVALID_ARGUMENT: Request contains an invalid argument
```

**Why This Happens**:
Trying to create trigger before connecting GitHub repo to Cloud Build.

**Solution**:

1. Go to Cloud Build → Triggers → Connect Repository
2. Authenticate with GitHub
3. Select repository
4. Then create trigger

---

### Pitfall 5: Package Lock File Missing

**Problem**:

```
npm error The `npm ci` command can only install with an existing package-lock.json
```

**Why This Happens**:
`npm ci` requires package-lock.json for reproducible builds.

**Solution**:

```bash
# Locally, generate lock file
npm install
git add package-lock.json
git commit -m "Add package-lock.json"
git push
```

---

### Pitfall 6: Jest Not Exiting

**Problem**:

```
Jest did not exit one second after the test run has completed
```

**Why This Happens**:
Express server starts when importing server.js for tests.

**Solution**:

```javascript
// In server.js:
if (require.main === module) {
  app.listen(PORT, "0.0.0.0");
}
module.exports = app;
```

Also add to jest.config.js:

```javascript
module.exports = {
  forceExit: true,
};
```

---

### Pitfall 7: Invalid Release ID

**Problem**:

```
ERROR: "order-api-release-" is not a valid resource ID
```

**Why This Happens**:
`SHORT_SHA` is only available for git-triggered builds, not manual submissions.

**Solution**:
Use timestamp or BUILD_ID instead:

```bash
RELEASE_ID=$(date +%Y%m%d-%H%M%S)
```

---

## Assessment Questions

### Conceptual Questions

1. **Explain the difference between CI and CD. Why do we need both?**

   <details>
   <summary>Answer</summary>

   - **CI** (Continuous Integration): Automatically builds and tests code on every commit to catch bugs early
   - **CD** (Continuous Deployment): Automatically deploys tested code to environments
   - **Why both**: CI ensures code quality, CD ensures fast, reliable deployments. Together they enable rapid, confident releases.
   </details>

2. **Why do we use multiple environments (dev, staging, prod)?**

   <details>
   <summary>Answer</summary>

   - **Dev**: Quick testing, experiments, can break
   - **Staging**: Pre-production validation, mirrors prod
   - **Prod**: Live users, must be stable
   - **Benefit**: Catch issues before they reach users, progressive validation
   </details>

3. **What is the purpose of a Docker container? Why not just deploy code directly?**

   <details>
   <summary>Answer</summary>

   - **Containers**: Package code + dependencies + runtime
   - **Benefits**:
     - Consistent across environments
     - Isolated from host system
     - Fast to start/stop
     - Portable (works anywhere)
   - **Without containers**: "Works on my machine" problems, dependency conflicts, environment drift
   </details>

4. **Explain Cloud Run's autoscaling. When would you use minScale: 0 vs minScale: 1?**

   <details>
   <summary>Answer</summary>

   - **minScale: 0**: Scales to zero, no idle costs, but cold starts
   - **minScale: 1**: Always at least 1 instance, costs more, no cold starts
   - **Use minScale: 0**: Dev/staging, low-traffic apps, cost-sensitive
   - **Use minScale: 1**: Production, latency-sensitive, critical services
   </details>

5. **Why do we need separate IAM service accounts? Can't we just use one?**

   <details>
   <summary>Answer</summary>

   - **Principle of least privilege**: Each component should have only the permissions it needs
   - **App service account**: Logs, metrics (no build/deploy permissions)
   - **Cloud Build SA**: Build, push images (no access to prod data)
   - **Cloud Deploy SA**: Deploy services (limited scope)
   - **Benefits**: Security, audit trail, easy to revoke, compliance
   </details>

### Practical Questions

6. **Your build is failing at the "run-tests" step. How would you debug this?**

   <details>
   <summary>Answer</summary>

   1. Check Cloud Build logs for error message
   2. Run tests locally: `npm test`
   3. Check if dependencies are installed
   4. Verify Node.js version matches (18)
   5. Check for environment-specific issues
   6. Look at recent code changes
   </details>

7. **How would you implement a gradual rollout to production (50% new, 50% old)?**

   <details>
   <summary>Answer</summary>

   ```yaml
   traffic:
     - revisionName: order-api-prod-00001
       percent: 50
     - revisionName: order-api-prod-00002
       percent: 50
   ```

   Or use Cloud Run console to adjust traffic split manually.
   </details>

8. **Your Cloud Run service is responding slowly. What would you check?**

   <details>
   <summary>Answer</summary>

   1. Check if cold starts (increase minScale)
   2. Look at CPU/memory usage (may need more resources)
   3. Check containerConcurrency (too high?)
   4. Review application code (slow queries?)
   5. Check database connection pooling
   6. Look at Cloud Run metrics in console
   </details>

9. **How would you add a new environment variable to all environments?**

   <details>
   <summary>Answer</summary>

   1. Add to each YAML file (cloudrun-service-dev.yaml, staging, prod)
   2. Under `spec.template.spec.containers[0].env`
   3. Commit and push changes
   4. Trigger new deployment
   5. Verify in each environment

   **Better approach**: Use Secret Manager for sensitive values
   </details>

10. **You need to rollback a production deployment. What steps would you take?**

    <details>
    <summary>Answer</summary>

    **Option 1: Cloud Deploy Rollback**

    ```bash
    gcloud deploy rollouts rollback ROLLOUT_NAME \
      --delivery-pipeline=order-api-pipeline \
      --release=PREVIOUS_RELEASE
    ```

    **Option 2: Traffic Shift**

    ```bash
    gcloud run services update-traffic order-api-prod \
      --to-revisions=order-api-prod-00001=100
    ```

    **Option 3**: Promote previous release through pipeline
    </details>

---

## Hands-On Exercises

### Exercise 1: Deploy Your First Service (30 minutes)

**Objective**: Get the complete pipeline working

**Steps**:

1. Fork the repository
2. Run `./setup.sh` to configure GCP
3. Trigger a build manually
4. Verify deployment to dev environment
5. Test the health endpoint
6. Test the orders endpoint

**Deliverable**: Screenshot of successful Cloud Run deployment

---

### Exercise 2: Add a New Endpoint (45 minutes)

**Objective**: Understand the full development cycle

**Task**: Add a `GET /orders/:id` endpoint

**Requirements**:

- Accept order ID in URL
- Return mock order data
- Add validation (ID must be valid format)
- Write unit tests
- Deploy through CI/CD pipeline

**Steps**:

1. Create new route handler
2. Add tests
3. Test locally
4. Commit and push
5. Monitor build in Cloud Build
6. Verify deployment in Cloud Run
7. Test the new endpoint

---

### Exercise 3: Configure Different Environments (30 minutes)

**Objective**: Understand environment-specific configurations

**Task**: Make staging use different resource limits than dev

**Steps**:

1. Edit `k8s/cloudrun-service-staging.yaml`
2. Change CPU to 2 cores, Memory to 2Gi
3. Change minScale to 2
4. Commit and deploy
5. Compare dev vs staging in Cloud Run console
6. Explain why you'd want different configs

---

### Exercise 4: Implement Blue-Green Deployment (45 minutes)

**Objective**: Learn advanced deployment strategies

**Task**: Deploy a new version alongside old version

**Steps**:

1. Make a visible change (return version in health check)
2. Deploy version 2 but keep version 1 running
3. Split traffic 50/50
4. Monitor error rates
5. Gradually increase traffic to version 2
6. Fully cut over to version 2

---

### Exercise 5: Troubleshooting (30 minutes)

**Objective**: Develop debugging skills

**Scenarios**:

1. Build fails in test step
2. Image push fails
3. Cloud Deploy rollout fails
4. Service returns 500 errors
5. Service is very slow

**Task**: For each scenario, document:

- Where to look for logs
- What to check
- How to fix
- How to prevent in future

---

## Further Learning

### Next Steps

1. **Add Database**

   - Cloud SQL (PostgreSQL)
   - Connection pooling
   - Database migrations

2. **Implement Caching**

   - Cloud Memorystore (Redis)
   - Reduce latency
   - Improve scalability

3. **Add Authentication**

   - Identity Platform
   - JWT tokens
   - Role-based access control

4. **Implement Observability**

   - Cloud Logging (structured logs)
   - Cloud Trace (distributed tracing)
   - Cloud Monitoring (custom metrics)
   - Error Reporting

5. **Advanced CI/CD**
   - Parallel builds
   - Build caching
   - Multi-region deployment
   - Automated rollbacks

### Recommended Resources

**Google Cloud**:

- [Cloud Build Documentation](https://cloud.google.com/build/docs)
- [Cloud Deploy Documentation](https://cloud.google.com/deploy/docs)
- [Cloud Run Documentation](https://cloud.google.com/run/docs)

**CI/CD Concepts**:

- [Continuous Delivery by Jez Humble](https://continuousdelivery.com/)
- [The DevOps Handbook](https://itrevolution.com/product/the-devops-handbook/)

**Kubernetes/Cloud Run**:

- [Knative Documentation](https://knative.dev/docs/)
- [12-Factor App Methodology](https://12factor.net/)

**Docker**:

- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Multi-stage Builds](https://docs.docker.com/build/building/multi-stage/)

---

## Lab Setup Checklist

### For Instructors

**Before Class**:

- [ ] Create GCP project for students
- [ ] Enable billing
- [ ] Grant students Editor role
- [ ] Verify API quotas
- [ ] Test setup.sh script
- [ ] Prepare troubleshooting guide

**During Class**:

- [ ] Verify all students can access GCP Console
- [ ] Check gcloud CLI is installed
- [ ] Ensure GitHub accounts are set up
- [ ] Monitor quota usage
- [ ] Be ready for common errors

**After Class**:

- [ ] Have students run cleanup.sh
- [ ] Verify all resources deleted
- [ ] Review billing
- [ ] Collect feedback

### For Students

**Prerequisites**:

- [ ] GCP account with billing enabled
- [ ] GitHub account
- [ ] gcloud CLI installed locally
- [ ] Node.js 18+ installed
- [ ] Docker installed (optional, for local testing)
- [ ] Code editor (VS Code recommended)

**Before Starting**:

- [ ] Authenticate: `gcloud auth login`
- [ ] Set project: `gcloud config set project PROJECT_ID`
- [ ] Clone repository
- [ ] Read README.md

---

## Glossary

**Artifact Registry**: Google Cloud's service for storing container images and other artifacts

**Cloud Build**: Fully managed CI/CD platform for building, testing, and deploying applications

**Cloud Deploy**: Managed continuous delivery service for deploying to Cloud Run, GKE, or Anthos

**Cloud Run**: Serverless platform for running stateless containers that automatically scale

**Container**: Packaged application with all dependencies, isolated from host system

**Delivery Pipeline**: Sequence of stages (dev → staging → prod) for deploying software

**Dockerfile**: Text file with instructions for building a Docker image

**IAM**: Identity and Access Management - controls who can access what in GCP

**Image**: Built container ready to run (immutable snapshot)

**Manifest**: YAML file describing how to deploy a service (Kubernetes/Cloud Run config)

**Release**: Specific version of software ready for deployment

**Revision**: Immutable snapshot of a Cloud Run service configuration

**Rollout**: Actual deployment of a release to a target environment

**Service Account**: Non-human identity used by applications/services

**Skaffold**: Tool for managing Kubernetes/Cloud Run configurations and deployments

**Substitution**: Variable in Cloud Build configuration that can be customized per trigger

**Target**: Destination environment in Cloud Deploy (dev, staging, prod)

---

## Summary

This class taught you how to build a complete CI/CD pipeline using Google Cloud Platform services. You learned:

1. **CI/CD Concepts**: Why automation matters, benefits of continuous delivery
2. **Cloud Services**: Cloud Build (CI), Cloud Deploy (CD), Cloud Run (runtime)
3. **Best Practices**: Multi-environment strategy, IAM security, testing
4. **Hands-On Skills**: Building, deploying, and troubleshooting real applications
5. **Production Ready**: Scalable, secure, maintainable pipeline

**Key Takeaways**:

- ✅ CI/CD enables fast, reliable software delivery
- ✅ Containers provide consistency across environments
- ✅ Serverless (Cloud Run) reduces operational overhead
- ✅ Progressive delivery (dev → staging → prod) reduces risk
- ✅ Proper IAM is critical for security
- ✅ Automation prevents human errors

**You're now ready to**:

- Build production-grade CI/CD pipelines
- Deploy containerized applications to Cloud Run
- Implement multi-environment deployment strategies
- Troubleshoot common deployment issues
- Apply DevOps best practices

---

**End of Class Notes**

_For questions, clarifications, or additional resources, please refer to the README.md or contact the instructor._
