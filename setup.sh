#!/bin/bash

# Setup script for Order API CI/CD pipeline on GCP
# This script automates the complete setup of Cloud Build, Cloud Deploy, and Cloud Run

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
SERVICE_NAME="order-api"
REGION="asia-south1"
REPO_NAME="order-api-repo"
SERVICE_ACCOUNT_NAME="order-api-sa"
PIPELINE_NAME="order-api-pipeline"

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    if ! command_exists gcloud; then
        print_error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    print_success "gcloud CLI is installed"
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        print_error "No active gcloud authentication found. Please run: gcloud auth login"
        exit 1
    fi
    
    print_success "gcloud authentication verified"
}

# Get or set project ID
get_project_id() {
    if [ -z "$PROJECT_ID" ]; then
        # Try to get default project from gcloud config
        CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)
        if [ -n "$CURRENT_PROJECT" ] && [ "$CURRENT_PROJECT" != "(unset)" ]; then
            PROJECT_ID=$CURRENT_PROJECT
            print_info "Using default project from gcloud config: $PROJECT_ID"
        else
            print_warning "No default project found in gcloud config"
            read -p "Enter your GCP Project ID: " PROJECT_ID
        fi
    fi
    
    if [ -z "$PROJECT_ID" ]; then
        print_error "Project ID is required"
        exit 1
    fi
    
    # Verify project exists and is accessible
    print_info "Verifying project access..."
    if ! gcloud projects describe "$PROJECT_ID" --quiet >/dev/null 2>&1; then
        print_error "Project '$PROJECT_ID' not found or not accessible"
        exit 1
    fi
    
    # Set project in gcloud config (in case it wasn't already set)
    gcloud config set project "$PROJECT_ID" --quiet >/dev/null 2>&1
    print_success "Using Project ID: $PROJECT_ID"
}

# Enable required APIs
enable_apis() {
    print_info "Enabling required GCP APIs..."
    
    gcloud services enable \
        cloudbuild.googleapis.com \
        clouddeploy.googleapis.com \
        run.googleapis.com \
        artifactregistry.googleapis.com \
        cloudresourcemanager.googleapis.com \
        iam.googleapis.com \
        --project="$PROJECT_ID" \
        --quiet
    
    print_success "All required APIs enabled"
}

# Create Artifact Registry repository
create_artifact_registry() {
    print_info "Creating Artifact Registry repository..."
    
    # Check if repository already exists
    if gcloud artifacts repositories describe "$REPO_NAME" \
        --location="$REGION" \
        --project="$PROJECT_ID" \
        --quiet >/dev/null 2>&1; then
        print_warning "Artifact Registry repository '$REPO_NAME' already exists, skipping..."
    else
        gcloud artifacts repositories create "$REPO_NAME" \
            --repository-format=docker \
            --location="$REGION" \
            --description="Docker repository for Order API" \
            --project="$PROJECT_ID" \
            --quiet
        
        print_success "Artifact Registry repository created"
    fi
}

# Create service account for Cloud Run
create_service_account() {
    print_info "Creating service account for Cloud Run..."
    
    # Check if service account already exists
    if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --project="$PROJECT_ID" \
        --quiet >/dev/null 2>&1; then
        print_warning "Service account '${SERVICE_ACCOUNT_NAME}' already exists, skipping creation..."
    else
        gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
            --display-name="Order API Service Account" \
            --description="Service account for Order API Cloud Run service" \
            --project="$PROJECT_ID" \
            --quiet
        
        print_success "Service account created"
    fi
    
    # Grant Cloud Run invoker role
    print_info "Granting Cloud Run invoker role to service account..."
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/run.invoker" \
        --condition=None \
        --quiet >/dev/null 2>&1 || true
    
    print_success "Service account permissions configured"
}

# Grant Cloud Build permissions
grant_cloud_build_permissions() {
    print_info "Granting permissions to Cloud Build service account..."
    
    CLOUD_BUILD_SA="${PROJECT_ID}@cloudbuild.gserviceaccount.com"
    
    # Grant Artifact Registry writer
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${CLOUD_BUILD_SA}" \
        --role="roles/artifactregistry.writer" \
        --condition=None \
        --quiet >/dev/null 2>&1 || true
    
    # Grant Cloud Run admin
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${CLOUD_BUILD_SA}" \
        --role="roles/run.admin" \
        --condition=None \
        --quiet >/dev/null 2>&1 || true
    
    # Grant Cloud Deploy releaser
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${CLOUD_BUILD_SA}" \
        --role="roles/clouddeploy.releaser" \
        --condition=None \
        --quiet >/dev/null 2>&1 || true
    
    # Grant Cloud Deploy job runner (needed for deployments)
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${CLOUD_BUILD_SA}" \
        --role="roles/clouddeploy.jobRunner" \
        --condition=None \
        --quiet >/dev/null 2>&1 || true
    
    # Grant service account user role
    gcloud iam service-accounts add-iam-policy-binding \
        "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --member="serviceAccount:${CLOUD_BUILD_SA}" \
        --role="roles/iam.serviceAccountUser" \
        --project="$PROJECT_ID" \
        --quiet >/dev/null 2>&1 || true
    
    print_success "Cloud Build permissions granted"
}

# Initialize Cloud Deploy
initialize_cloud_deploy() {
    print_info "Initializing Cloud Deploy pipeline..."
    
    # Check if pipeline already exists
    if gcloud deploy pipelines describe "$PIPELINE_NAME" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --quiet >/dev/null 2>&1; then
        print_warning "Cloud Deploy pipeline '$PIPELINE_NAME' already exists, skipping..."
    else
        # Replace PROJECT_ID placeholder in clouddeploy.yaml
        if [ -f "clouddeploy.yaml" ]; then
            sed "s/\${PROJECT_ID}/$PROJECT_ID/g" clouddeploy.yaml > clouddeploy-temp.yaml
            
            gcloud deploy apply \
                --file=clouddeploy-temp.yaml \
                --region="$REGION" \
                --project="$PROJECT_ID" \
                --quiet
            
            rm -f clouddeploy-temp.yaml
            print_success "Cloud Deploy pipeline initialized"
        else
            print_error "clouddeploy.yaml not found in current directory"
            exit 1
        fi
    fi
}

# Create Cloud Build trigger (optional)
create_cloud_build_trigger() {
    print_info "Setting up Cloud Build trigger..."
    
    read -p "Do you want to create a Cloud Build trigger? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Skipping Cloud Build trigger creation"
        return
    fi
    
    read -p "Enter your Git repository URL (e.g., https://github.com/user/repo.git): " REPO_URL
    if [ -z "$REPO_URL" ]; then
        print_warning "No repository URL provided, skipping trigger creation"
        return
    fi
    
    read -p "Enter branch name to trigger on (default: main): " BRANCH_NAME
    BRANCH_NAME=${BRANCH_NAME:-main}
    
    # Extract repo name and owner from URL
    if [[ $REPO_URL =~ github\.com[:/]([^/]+)/([^/]+)\.git ]] || [[ $REPO_URL =~ github\.com[:/]([^/]+)/([^/]+)$ ]]; then
        REPO_OWNER="${BASH_REMATCH[1]}"
        GIT_REPO_NAME="${BASH_REMATCH[2]}"
        
        print_info "Creating Cloud Build trigger for $REPO_OWNER/$GIT_REPO_NAME on branch $BRANCH_NAME..."
        
        # Check if trigger already exists
        TRIGGER_EXISTS=$(gcloud builds triggers list --project="$PROJECT_ID" --format="value(name)" 2>/dev/null | grep -x "order-api-trigger" || true)
        
        if [ -n "$TRIGGER_EXISTS" ]; then
            print_warning "Trigger 'order-api-trigger' already exists, skipping..."
        else
            gcloud builds triggers create github \
                --name="order-api-trigger" \
                --repo-name="$GIT_REPO_NAME" \
                --repo-owner="$REPO_OWNER" \
                --branch-pattern="^${BRANCH_NAME}$" \
                --build-config="cloudbuild.yaml" \
                --substitutions="_SERVICE_NAME=$SERVICE_NAME,_REGION=$REGION,_REPO_NAME=$REPO_NAME" \
                --project="$PROJECT_ID" \
                --quiet
            
            print_success "Cloud Build trigger created"
        fi
    else
        print_warning "Could not parse repository URL, skipping trigger creation"
        print_info "You can create the trigger manually using:"
        print_info "gcloud builds triggers create github --name=order-api-trigger --repo-name=REPO --repo-owner=OWNER --branch-pattern=^main$ --build-config=cloudbuild.yaml"
    fi
}

# Print summary
print_summary() {
    echo
    print_success "========================================="
    print_success "Setup completed successfully!"
    print_success "========================================="
    echo
    print_info "Project ID: $PROJECT_ID"
    print_info "Region: $REGION"
    print_info "Service Name: $SERVICE_NAME"
    print_info "Artifact Registry: $REPO_NAME"
    print_info "Service Account: ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    echo
    print_info "Next steps:"
    echo "  1. Verify the setup: gcloud deploy pipelines describe $PIPELINE_NAME --region=$REGION"
    echo "  2. Test the build: gcloud builds submit --config=cloudbuild.yaml"
    echo "  3. View Cloud Run services: gcloud run services list --region=$REGION"
    echo
    print_info "For manual deployment, run:"
    echo "  gcloud builds submit --config=cloudbuild.yaml --substitutions=_SERVICE_NAME=$SERVICE_NAME,_REGION=$REGION,_REPO_NAME=$REPO_NAME,_IMAGE_TAG=\$(git rev-parse --short HEAD)"
    echo
}

# Main execution
main() {
    echo
    print_info "========================================="
    print_info "Order API CI/CD Pipeline Setup"
    print_info "========================================="
    echo
    
    check_prerequisites
    get_project_id
    enable_apis
    create_artifact_registry
    create_service_account
    grant_cloud_build_permissions
    initialize_cloud_deploy
    create_cloud_build_trigger
    print_summary
}

# Run main function
main

