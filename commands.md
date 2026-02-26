# Step-by-Step Setup Commands

This document contains all the commands needed to set up the complete CI/CD pipeline for the Order API microservice on GCP.

> **📝 Note:** These manual commands are synchronized with `setup.sh` (automated script). You can either:
> - **Follow this guide manually** for full control and learning
> - **Run `./setup.sh`** for automated setup (recommended for quick start)
>
> The automated script (`setup.sh`) combines these steps with:
> - ✅ Automatic project ID detection
> - ✅ Idempotency (safe to run multiple times)
> - ✅ Interactive prompts and validation
> - ✅ Better error handling and colored output

## Prerequisites

Before starting, ensure you have:
- Google Cloud SDK (`gcloud`) installed
- Git installed
- A GCP project created
- GitHub repository created (for automatic triggers)

## Step 1: Configure GCP Project

```bash
# Set your project ID
export PROJECT_ID="upgradlabs-1749732688326"  # Replace with your actual project ID

# Or use the current gcloud config project
export PROJECT_ID=$(gcloud config get-value project)

# Verify project
echo "Using project: $PROJECT_ID"

# Set the project
gcloud config set project $PROJECT_ID

# Set your preferred region
export REGION="asia-south1"  # Change if needed
gcloud config set compute/region $REGION
```

## Step 2: Enable Required APIs

```bash
# Enable all required GCP APIs
gcloud services enable \
    cloudbuild.googleapis.com \
    clouddeploy.googleapis.com \
    run.googleapis.com \
    artifactregistry.googleapis.com \
    containerregistry.googleapis.com \
    iam.googleapis.com \
    cloudresourcemanager.googleapis.com

# Wait for APIs to be fully enabled (takes 1-2 minutes)
echo "Waiting for APIs to be enabled..."
sleep 60
```

## Step 3: Clone the Repository

```bash
# Clone your repository
git clone https://github.com/debayankundu99-sys/hello-cloud-deploy.git
cd hello-cloud-deploy

# Install Node.js dependencies locally (optional, for local testing)
npm install
```

## Step 4: Configure Variables

```bash
# Set configuration variables
export SERVICE_NAME="order-api"
export REPO_NAME="order-api-repo"
export SERVICE_ACCOUNT_NAME="order-api-sa"
export PIPELINE_NAME="order-api-pipeline"
```

## Step 5: Create Artifact Registry

```bash
# Create Docker repository in Artifact Registry
gcloud artifacts repositories create $REPO_NAME \
    --repository-format=docker \
    --location=$REGION \
    --description="Docker repository for Order API" \
    --project=$PROJECT_ID

# Verify repository creation
gcloud artifacts repositories describe $REPO_NAME \
    --location=$REGION \
    --project=$PROJECT_ID
```

## Step 6: Create Service Account

```bash
# Create service account for the application
gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
    --display-name="Order API Service Account" \
    --description="Service account for Order API microservice" \
    --project=$PROJECT_ID

# Grant necessary permissions to the service account
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/logging.logWriter"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/cloudtrace.agent"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/monitoring.metricWriter"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/run.invoker"
```

## Step 7: Grant Cloud Build and Cloud Deploy Permissions

```bash
# Set Cloud Build service account variable
export CLOUD_BUILD_SA="${PROJECT_ID}@cloudbuild.gserviceaccount.com"

# Grant Cloud Build permissions
echo "Granting Cloud Build permissions..."

# Grant Artifact Registry writer
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${CLOUD_BUILD_SA}" \
    --role="roles/artifactregistry.writer" \
    --condition=None

# Grant Cloud Run admin
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${CLOUD_BUILD_SA}" \
    --role="roles/run.admin" \
    --condition=None

# Grant Cloud Deploy releaser
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${CLOUD_BUILD_SA}" \
    --role="roles/clouddeploy.releaser" \
    --condition=None

# Grant Cloud Deploy job runner
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${CLOUD_BUILD_SA}" \
    --role="roles/clouddeploy.jobRunner" \
    --condition=None

# Grant service account user role to Cloud Build
gcloud iam service-accounts add-iam-policy-binding \
    ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
    --member="serviceAccount:${CLOUD_BUILD_SA}" \
    --role="roles/iam.serviceAccountUser" \
    --project=$PROJECT_ID

# Grant Cloud Deploy service agent permissions
echo "Granting Cloud Deploy service agent permissions..."

# Get project number
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

# Set Cloud Deploy service agent variable
export CLOUD_DEPLOY_SA="service-${PROJECT_NUMBER}@gcp-sa-clouddeploy.iam.gserviceaccount.com"

echo "Cloud Deploy service agent: $CLOUD_DEPLOY_SA"

# Grant Cloud Deploy service agent permission to act as the service account
gcloud iam service-accounts add-iam-policy-binding \
    ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
    --member="serviceAccount:${CLOUD_DEPLOY_SA}" \
    --role="roles/iam.serviceAccountUser" \
    --project=$PROJECT_ID

# Grant Cloud Deploy service agent Cloud Run developer role
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${CLOUD_DEPLOY_SA}" \
    --role="roles/run.developer" \
    --condition=None

echo "✓ Cloud Build and Cloud Deploy permissions granted"
```

## Step 8: Initialize Cloud Deploy Pipeline

```bash
# Replace PROJECT_ID placeholder in clouddeploy.yaml
sed "s/\${PROJECT_ID}/$PROJECT_ID/g" clouddeploy.yaml > clouddeploy-temp.yaml

# View the updated configuration (optional)
cat clouddeploy-temp.yaml
```

## Step 9: Create Cloud Deploy Pipeline and Targets

```bash
# Create Cloud Deploy pipeline and targets
gcloud deploy apply \
    --file=clouddeploy-temp.yaml \
    --region=$REGION \
    --project=$PROJECT_ID

# Verify pipeline creation
gcloud deploy delivery-pipelines describe $PIPELINE_NAME \
    --region=$REGION \
    --project=$PROJECT_ID

# List all targets
gcloud deploy targets list --region=$REGION --project=$PROJECT_ID

# Clean up temp file
rm -f clouddeploy-temp.yaml
```

## Step 10: Connect GitHub Repository to Cloud Build

**⚠️ IMPORTANT: This step must be done via the Console before creating triggers**

This is a one-time setup that requires browser authentication.

### Steps to connect your repository:

1. Go to: https://console.cloud.google.com/cloud-build/triggers/connect
   - Replace with your project: `https://console.cloud.google.com/cloud-build/triggers/connect?project=$PROJECT_ID`
2. Click "**Connect Repository**"
3. Select "**GitHub**" as the source
4. **Authenticate with GitHub** (authorize Google Cloud Build)
5. Select your organization/user
6. Select your repository: `YOUR-USERNAME/hello-cloud-deploy`
7. Check "**I understand...**" and click "**Connect**"

```bash
# After connecting via console, verify the connection (optional)
gcloud alpha builds connections list --region=$REGION
```

## Step 11: Create Cloud Build Trigger

```bash
# Set GitHub repository details
export GIT_REPO_OWNER="debayankundu99-sys"  # Replace with your GitHub username
export GIT_REPO_NAME="hello-cloud-deploy"
export BRANCH_NAME="main"

# Create the Cloud Build trigger (only after GitHub is connected)
gcloud builds triggers create github \
    --name="${SERVICE_NAME}-trigger" \
    --repo-owner="$GIT_REPO_OWNER" \
    --repo-name="$GIT_REPO_NAME" \
    --branch-pattern="^${BRANCH_NAME}$" \
    --build-config="cloudbuild.yaml" \
    --substitutions="_SERVICE_NAME=${SERVICE_NAME},_REGION=${REGION},_REPO_NAME=${REPO_NAME}" \
    --region=$REGION

# Verify trigger creation
gcloud builds triggers describe ${SERVICE_NAME}-trigger --region=$REGION

# List all triggers
gcloud builds triggers list --region=$REGION
```

## Step 12: Test the Build Pipeline

```bash
# Option 1: Manual build submission
gcloud builds submit \
    --config=cloudbuild.yaml \
    --substitutions="_SERVICE_NAME=${SERVICE_NAME},_REGION=${REGION},_REPO_NAME=${REPO_NAME}"

# Option 2: Trigger via Git push
git add .
git commit -m "Trigger CI/CD pipeline"
git push origin main
```

## Step 13: Monitor the Build

```bash
# List recent builds
gcloud builds list --limit=5

# Get specific build details (replace BUILD_ID with actual ID)
gcloud builds describe BUILD_ID

# Stream build logs
gcloud builds log BUILD_ID --stream
```

## Step 14: Monitor Cloud Deploy Release

```bash
# List all releases
gcloud deploy releases list \
    --delivery-pipeline=$PIPELINE_NAME \
    --region=$REGION

# Describe a specific release (replace RELEASE_NAME)
gcloud deploy releases describe RELEASE_NAME \
    --delivery-pipeline=$PIPELINE_NAME \
    --region=$REGION

# List rollouts for a release
gcloud deploy rollouts list \
    --delivery-pipeline=$PIPELINE_NAME \
    --release=RELEASE_NAME \
    --region=$REGION
```

## Step 15: Verify Cloud Run Deployment

```bash
# List Cloud Run services
gcloud run services list --region=$REGION

# Get service details for dev environment
gcloud run services describe order-api-dev \
    --region=$REGION \
    --format="value(status.url)"

# Test the deployed service
export DEV_URL=$(gcloud run services describe order-api-dev \
    --region=$REGION \
    --format="value(status.url)")

# Test health endpoint
curl ${DEV_URL}/health

# Test orders endpoint
curl -X POST ${DEV_URL}/orders \
    -H "Content-Type: application/json" \
    -d '{
        "customerId": "cust-123",
        "items": [
            {"productId": "prod-1", "quantity": 2, "price": 29.99}
        ],
        "totalAmount": 59.98
    }'
```

## Step 16: Promote to Staging

```bash
# Get the latest release name
export RELEASE_NAME=$(gcloud deploy releases list \
    --delivery-pipeline=$PIPELINE_NAME \
    --region=$REGION \
    --format="value(name)" \
    --limit=1)

# Promote to staging
gcloud deploy releases promote \
    --release=$RELEASE_NAME \
    --delivery-pipeline=$PIPELINE_NAME \
    --region=$REGION \
    --to-target=order-api-staging

# Monitor the rollout
gcloud deploy rollouts list \
    --delivery-pipeline=$PIPELINE_NAME \
    --release=$RELEASE_NAME \
    --region=$REGION
```

## Step 17: Promote to Production (with approval)

```bash
# Promote to production (requires approval)
gcloud deploy releases promote \
    --release=$RELEASE_NAME \
    --delivery-pipeline=$PIPELINE_NAME \
    --region=$REGION \
    --to-target=order-api-prod

# Approve the production deployment
export ROLLOUT_NAME=$(gcloud deploy rollouts list \
    --delivery-pipeline=$PIPELINE_NAME \
    --release=$RELEASE_NAME \
    --region=$REGION \
    --filter="targetId:order-api-prod" \
    --format="value(name)" \
    --limit=1)

gcloud deploy rollouts approve $ROLLOUT_NAME \
    --delivery-pipeline=$PIPELINE_NAME \
    --release=$RELEASE_NAME \
    --region=$REGION
```

## Step 18: View Logs

```bash
# View Cloud Run logs for dev environment
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=order-api-dev" \
    --limit=50 \
    --format=json

# Follow logs in real-time
gcloud alpha run services logs tail order-api-dev --region=$REGION

# View Cloud Build logs
gcloud builds log $(gcloud builds list --limit=1 --format="value(id)") --stream
```

## Step 19: Cleanup (Optional)

```bash
# Use the cleanup script
./cleanup.sh

# Or manually delete resources:

# Delete Cloud Run services
gcloud run services delete order-api-dev --region=$REGION --quiet
gcloud run services delete order-api-stg --region=$REGION --quiet
gcloud run services delete order-api-prod --region=$REGION --quiet

# Delete Cloud Deploy resources
gcloud deploy delivery-pipelines delete $PIPELINE_NAME --region=$REGION --quiet --force
gcloud deploy targets delete order-api-dev --region=$REGION --quiet
gcloud deploy targets delete order-api-staging --region=$REGION --quiet
gcloud deploy targets delete order-api-prod --region=$REGION --quiet

# Delete Artifact Registry repository
gcloud artifacts repositories delete $REPO_NAME --location=$REGION --quiet

# Delete service account
gcloud iam service-accounts delete ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com --quiet

# Delete Cloud Build trigger
gcloud builds triggers delete ${SERVICE_NAME}-trigger --region=$REGION --quiet
```

---

## Quick Reference

### Common Commands

```bash
# View all resources
gcloud deploy delivery-pipelines list --region=$REGION
gcloud deploy targets list --region=$REGION
gcloud run services list --region=$REGION
gcloud artifacts repositories list --location=$REGION

# Trigger a new build
gcloud builds submit --config=cloudbuild.yaml

# View latest release
gcloud deploy releases list --delivery-pipeline=$PIPELINE_NAME --region=$REGION --limit=1

# View service URLs
gcloud run services list --region=$REGION --format="table(name,status.url)"
```

### Environment Variables Summary

```bash
export PROJECT_ID="your-project-id"
export REGION="asia-south1"
export SERVICE_NAME="order-api"
export REPO_NAME="order-api-repo"
export SERVICE_ACCOUNT_NAME="order-api-sa"
export PIPELINE_NAME="order-api-pipeline"
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
export CLOUD_BUILD_SA="${PROJECT_ID}@cloudbuild.gserviceaccount.com"
export CLOUD_DEPLOY_SA="service-${PROJECT_NUMBER}@gcp-sa-clouddeploy.iam.gserviceaccount.com"
```

### Troubleshooting Commands

```bash
# Check API status
gcloud services list --enabled | grep -E "cloudbuild|clouddeploy|run|artifactregistry"

# Check IAM permissions
gcloud projects get-iam-policy $PROJECT_ID --flatten="bindings[].members" --filter="bindings.members:${CLOUD_BUILD_SA}"

# Check service account permissions
gcloud iam service-accounts get-iam-policy ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com

# Describe failed build
gcloud builds describe BUILD_ID

# Check Cloud Deploy operation status
gcloud deploy operations list --region=$REGION
```

---

## Automated Setup (Alternative)

Instead of running all commands manually, you can use the provided setup script:

```bash
# For Linux/Mac
chmod +x setup.sh
./setup.sh

# For Windows
setup.bat
```

The setup script will:
1. ✅ Detect your project ID automatically
2. ✅ Enable all required APIs
3. ✅ Create Artifact Registry repository
4. ✅ Create and configure service account
5. ✅ Grant all necessary IAM permissions
6. ✅ Initialize Cloud Deploy pipeline
7. ✅ Guide you through trigger creation

---

## Next Steps

After completing the setup:

1. **Test the service locally**:
   ```bash
   npm install
   npm test
   npm start
   ```

2. **Make changes and deploy**:
   ```bash
   git add .
   git commit -m "Your changes"
   git push origin main
   ```

3. **Monitor the pipeline**:
   - Cloud Build: https://console.cloud.google.com/cloud-build/builds
   - Cloud Deploy: https://console.cloud.google.com/deploy/delivery-pipelines
   - Cloud Run: https://console.cloud.google.com/run

4. **View application**:
   ```bash
   # Get the service URL
   gcloud run services describe order-api-dev \
       --region=$REGION \
       --format="value(status.url)"
   ```

---

**For more information, see [README.md](README.md)**

