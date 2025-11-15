# Order API - GCP Cloud Deploy CI/CD Setup

Enterprise-ready CI/CD pipeline for a containerized microservice using Google Cloud Platform services.

## Architecture Overview

```
Code Push → Cloud Build → Artifact Registry → Cloud Deploy → Cloud Run
                                                                    ↓
                                              dev → staging → prod
```

- **Cloud Build**: Runs tests, builds Docker image, pushes to Artifact Registry, creates Cloud Deploy release
- **Cloud Deploy**: Manages deployment pipeline across dev, staging, and production environments
- **Cloud Run**: Serverless container runtime for each environment
- **Artifact Registry**: Stores Docker images
- **Skaffold**: Generates Cloud Run manifests with environment-specific configurations

## Prerequisites

- Google Cloud Platform account with billing enabled
- `gcloud` CLI installed and configured
- Project ID set in GCP
- Appropriate IAM permissions (Cloud Build Admin, Cloud Deploy Admin, Cloud Run Admin, Artifact Registry Admin)

## Quick Setup (Automated)

For automated setup, use the provided setup scripts:

### Linux/macOS (Bash)

```bash
./setup.sh
```

### Windows (Batch)

```cmd
setup.bat
```

The setup scripts will:

- Check prerequisites (gcloud CLI, authentication)
- **Automatically use default PROJECT_ID from gcloud config** (or prompt if not set)
- Enable all required APIs
- Create Artifact Registry repository
- Create and configure service accounts
- Grant necessary IAM permissions
- Initialize Cloud Deploy pipeline
- Optionally create Cloud Build trigger

**Note:** The scripts automatically detect and use your default GCP project from `gcloud config`. You can also:

- Set `PROJECT_ID` environment variable to override: `export PROJECT_ID=your-project-id`
- Or manually set it: `gcloud config set project your-project-id`

## Cleanup

To remove all resources created by the setup script, use the cleanup script:

### Linux/macOS (Bash)

```bash
./cleanup.sh
```

The cleanup script will:

- Delete Cloud Deploy pipeline and all targets
- Delete Cloud Run services (dev, staging, prod)
- Delete Artifact Registry repository
- Delete service account
- Delete Cloud Build trigger (if exists)
- Remove IAM policy bindings

**Warning:** This will permanently delete all resources. The script will ask for confirmation before proceeding.

## Manual Setup

If you prefer to set up manually or need to customize the configuration, follow the steps below:

### 1. Enable Required APIs

```bash
# Set your project ID
export PROJECT_ID=your-project-id
gcloud config set project $PROJECT_ID

# Enable required APIs
gcloud services enable \
  cloudbuild.googleapis.com \
  clouddeploy.googleapis.com \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com
```

### 2. Create Artifact Registry Repository

```bash
# Create Docker repository in asia-south1
gcloud artifacts repositories create order-api-repo \
  --repository-format=docker \
  --location=asia-south1 \
  --description="Docker repository for Order API"
```

### 3. Create Service Account for Cloud Run

```bash
# Create service account
gcloud iam service-accounts create order-api-sa \
  --display-name="Order API Service Account" \
  --description="Service account for Order API Cloud Run service"

# Grant necessary permissions (adjust as needed)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:order-api-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/run.invoker"
```

### 4. Grant Cloud Build Permissions

```bash
# Get Cloud Build service account
export CLOUD_BUILD_SA="${PROJECT_ID}@cloudbuild.gserviceaccount.com"

# Grant Cloud Build permission to push to Artifact Registry
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${CLOUD_BUILD_SA}" \
  --role="roles/artifactregistry.writer"

# Grant Cloud Build permission to deploy to Cloud Run
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${CLOUD_BUILD_SA}" \
  --role="roles/run.admin"

# Grant Cloud Build permission to use Cloud Deploy
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${CLOUD_BUILD_SA}" \
  --role="roles/clouddeploy.releaser"

# Grant Cloud Build permission to act as Cloud Run service account
gcloud iam service-accounts add-iam-policy-binding \
  order-api-sa@${PROJECT_ID}.iam.gserviceaccount.com \
  --member="serviceAccount:${CLOUD_BUILD_SA}" \
  --role="roles/iam.serviceAccountUser"
```

### 5. Initialize Cloud Deploy

```bash
# Apply Cloud Deploy pipeline configuration
gcloud deploy apply \
  --file=clouddeploy.yaml \
  --region=asia-south1 \
  --project=$PROJECT_ID
```

### 6. Create Cloud Build Trigger

#### Option A: Manual Trigger

```bash
# Submit build manually
gcloud builds submit \
  --config=cloudbuild.yaml \
  --substitutions=_SERVICE_NAME=order-api,_REGION=asia-south1,_REPO_NAME=order-api-repo,_IMAGE_TAG=$(git rev-parse --short HEAD)
```

#### Option B: Automatic Trigger on Git Push

```bash
# Connect repository (if using Cloud Source Repositories)
gcloud source repos create order-api-repo

# Or connect to GitHub/Bitbucket (via Console or gcloud)
# Then create trigger:
gcloud builds triggers create github \
  --name="order-api-trigger" \
  --repo-name="your-repo-name" \
  --repo-owner="your-github-username" \
  --branch-pattern="^main$" \
  --build-config="cloudbuild.yaml" \
  --substitutions="_SERVICE_NAME=order-api,_REGION=asia-south1,_REPO_NAME=order-api-repo"
```

## Deployment Workflow

### Automatic Deployment to Dev

When code is pushed to the main branch:

1. Cloud Build trigger fires
2. Tests are run
3. Docker image is built and pushed to Artifact Registry
4. Cloud Deploy release is created
5. Automatic deployment to `order-api-dev` begins

### Promote to Staging

```bash
# List releases
gcloud deploy releases list \
  --delivery-pipeline=order-api-pipeline \
  --region=asia-south1

# Promote release from dev to staging
gcloud deploy releases promote \
  --release=order-api-release-<RELEASE_ID> \
  --delivery-pipeline=order-api-pipeline \
  --region=asia-south1 \
  --to-target=order-api-staging
```

### Promote to Production

```bash
# Promote release from staging to production (requires approval)
gcloud deploy releases promote \
  --release=order-api-release-<RELEASE_ID> \
  --delivery-pipeline=order-api-pipeline \
  --region=asia-south1 \
  --to-target=order-api-prod

# Approve the promotion (if approval is required)
gcloud deploy releases approve \
  --release=order-api-release-<RELEASE_ID> \
  --delivery-pipeline=order-api-pipeline \
  --region=asia-south1
```

## Monitoring Deployments

```bash
# View delivery pipeline status
gcloud deploy pipelines describe order-api-pipeline \
  --region=asia-south1

# View releases
gcloud deploy releases list \
  --delivery-pipeline=order-api-pipeline \
  --region=asia-south1

# View rollouts
gcloud deploy rollouts list \
  --delivery-pipeline=order-api-pipeline \
  --release=order-api-release-<RELEASE_ID> \
  --region=asia-south1

# View Cloud Run services
gcloud run services list --region=asia-south1
```

## Rollback Procedures

### Rollback in Cloud Deploy

```bash
# View previous releases
gcloud deploy releases list \
  --delivery-pipeline=order-api-pipeline \
  --region=asia-south1

# Promote a previous release to rollback
gcloud deploy releases promote \
  --release=order-api-release-<PREVIOUS_RELEASE_ID> \
  --delivery-pipeline=order-api-pipeline \
  --region=asia-south1 \
  --to-target=order-api-prod
```

### Manual Rollback in Cloud Run

```bash
# List revisions
gcloud run revisions list \
  --service=order-api-prod \
  --region=asia-south1

# Update traffic to point to previous revision
gcloud run services update-traffic order-api-prod \
  --region=asia-south1 \
  --to-revisions=<PREVIOUS_REVISION>=100
```

## Local Development

### Install Dependencies

```bash
npm install
```

### Run Locally

```bash
# Development mode with auto-reload
npm run dev

# Production mode
npm start
```

### Run Tests

```bash
# Run tests once
npm test

# Run tests in watch mode
npm run test:watch
```

### Build and Test Docker Image Locally

```bash
# Build image
docker build -t order-api:local .

# Run container
docker run -p 8080:8080 -e SERVICE_ENV=local order-api:local

# Test endpoints
curl http://localhost:8080/health
curl -X POST http://localhost:8080/orders \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": "CUST-001",
    "items": [{"productId": "PROD-001", "quantity": 2, "price": 29.99}],
    "totalAmount": 59.98
  }'
```

## Service Endpoints

### Health Check

```
GET /health
```

### Create Order

```
POST /orders
Content-Type: application/json

{
  "customerId": "string",
  "items": [
    {
      "productId": "string",
      "quantity": number,
      "price": number
    }
  ],
  "totalAmount": number
}
```

### Get All Orders

```
GET /orders
```

## Environment Variables

- `PORT`: Server port (default: 8080)
- `SERVICE_ENV`: Environment name (dev, staging, prod)

## Project Structure

```
.
├── src/
│   ├── server.js              # Express server entry point
│   ├── routes/
│   │   ├── health.js          # Health check endpoint
│   │   └── orders.js          # Order endpoints
│   └── __tests__/
│       └── server.test.js     # Unit tests
├── k8s/
│   └── cloudrun-service.yaml  # Cloud Run service manifest
├── cloudbuild.yaml            # Cloud Build configuration
├── clouddeploy.yaml           # Cloud Deploy pipeline
├── skaffold.yaml              # Skaffold configuration
├── Dockerfile                 # Production Docker image
├── package.json               # Node.js dependencies
└── README.md                  # This file
```

## Troubleshooting

### Build Failures

```bash
# View build logs
gcloud builds list --limit=10
gcloud builds log <BUILD_ID>
```

### Deployment Failures

```bash
# View deployment logs
gcloud deploy rollouts describe <ROLLOUT_ID> \
  --delivery-pipeline=order-api-pipeline \
  --release=order-api-release-<RELEASE_ID> \
  --region=asia-south1
```

### Cloud Run Service Issues

```bash
# View service logs
gcloud run services describe order-api-prod \
  --region=asia-south1

# View logs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=order-api-prod" \
  --limit=50 \
  --format=json
```

## Security Best Practices

1. **Service Account**: Uses dedicated service account with minimal permissions
2. **Non-root User**: Dockerfile runs as non-root user
3. **Image Scanning**: Enable Artifact Registry vulnerability scanning
4. **IAM**: Follow principle of least privilege
5. **Secrets**: Use Secret Manager for sensitive data (not implemented in this example)

## Cost Optimization

- Cloud Run scales to zero when not in use
- Use appropriate CPU and memory limits
- Consider using Cloud Run min instances for production to avoid cold starts
- Monitor and optimize resource allocation

## Support

For issues or questions, refer to:

- [Cloud Build Documentation](https://cloud.google.com/build/docs)
- [Cloud Deploy Documentation](https://cloud.google.com/deploy/docs)
- [Cloud Run Documentation](https://cloud.google.com/run/docs)
