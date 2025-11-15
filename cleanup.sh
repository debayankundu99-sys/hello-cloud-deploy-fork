#!/bin/bash

# Cleanup script for Order API CI/CD pipeline on GCP
# This script removes all resources created by setup.sh

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables (should match setup.sh)
SERVICE_NAME="order-api"
REGION="asia-south1"
REPO_NAME="order-api-repo"
SERVICE_ACCOUNT_NAME="order-api-sa"
PIPELINE_NAME="order-api-pipeline"
TRIGGER_NAME="order-api-trigger"

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
        print_error "gcloud CLI is not installed"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        print_error "No active gcloud authentication found"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Get project ID
get_project_id() {
    if [ -z "$PROJECT_ID" ]; then
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
    
    print_info "Using Project ID: $PROJECT_ID"
    gcloud config set project "$PROJECT_ID" --quiet >/dev/null 2>&1
}

# Confirm deletion
confirm_deletion() {
    echo
    print_warning "========================================="
    print_warning "WARNING: This will delete all resources!"
    print_warning "========================================="
    echo
    print_info "The following resources will be deleted:"
    echo "  - Cloud Deploy pipeline: $PIPELINE_NAME"
    echo "  - Cloud Deploy targets: order-api-dev, order-api-staging, order-api-prod"
    echo "  - Cloud Run services: order-api-dev, order-api-stg, order-api-prod"
    echo "  - Artifact Registry repository: $REPO_NAME"
    echo "  - Service account: ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    echo "  - Cloud Build trigger: $TRIGGER_NAME (if exists)"
    echo "  - IAM policy bindings (will be removed)"
    echo
    read -p "Are you sure you want to continue? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        print_info "Cleanup cancelled"
        exit 0
    fi
}

# Delete Cloud Run services
delete_cloud_run_services() {
    print_info "Deleting Cloud Run services..."
    
    SERVICES=("order-api-dev" "order-api-stg" "order-api-prod")
    
    for SERVICE in "${SERVICES[@]}"; do
        if gcloud run services describe "$SERVICE" \
            --region="$REGION" \
            --project="$PROJECT_ID" \
            --quiet >/dev/null 2>&1; then
            print_info "Deleting Cloud Run service: $SERVICE"
            gcloud run services delete "$SERVICE" \
                --region="$REGION" \
                --project="$PROJECT_ID" \
                --quiet || print_warning "Failed to delete $SERVICE"
        else
            print_info "Cloud Run service $SERVICE does not exist, skipping..."
        fi
    done
    
    print_success "Cloud Run services cleanup completed"
}

# Delete Cloud Deploy pipeline and targets
delete_cloud_deploy() {
    print_info "Deleting Cloud Deploy pipeline and targets..."
    
    # Delete pipeline (this will also handle targets if they're part of the pipeline)
    if gcloud deploy pipelines describe "$PIPELINE_NAME" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --quiet >/dev/null 2>&1; then
        print_info "Deleting Cloud Deploy pipeline: $PIPELINE_NAME"
        gcloud deploy pipelines delete "$PIPELINE_NAME" \
            --region="$REGION" \
            --project="$PROJECT_ID" \
            --quiet || print_warning "Failed to delete pipeline"
    else
        print_info "Pipeline $PIPELINE_NAME does not exist, skipping..."
    fi
    
    # Delete targets individually (in case pipeline deletion didn't remove them)
    TARGETS=("order-api-dev" "order-api-staging" "order-api-prod")
    
    for TARGET in "${TARGETS[@]}"; do
        if gcloud deploy targets describe "$TARGET" \
            --region="$REGION" \
            --project="$PROJECT_ID" \
            --quiet >/dev/null 2>&1; then
            print_info "Deleting Cloud Deploy target: $TARGET"
            gcloud deploy targets delete "$TARGET" \
                --region="$REGION" \
                --project="$PROJECT_ID" \
                --quiet || print_warning "Failed to delete target $TARGET"
        fi
    done
    
    print_success "Cloud Deploy cleanup completed"
}

# Delete Artifact Registry repository
delete_artifact_registry() {
    print_info "Deleting Artifact Registry repository..."
    
    if gcloud artifacts repositories describe "$REPO_NAME" \
        --location="$REGION" \
        --project="$PROJECT_ID" \
        --quiet >/dev/null 2>&1; then
        print_info "Deleting Artifact Registry repository: $REPO_NAME"
        gcloud artifacts repositories delete "$REPO_NAME" \
            --location="$REGION" \
            --project="$PROJECT_ID" \
            --quiet || print_warning "Failed to delete repository"
    else
        print_info "Artifact Registry repository $REPO_NAME does not exist, skipping..."
    fi
    
    print_success "Artifact Registry cleanup completed"
}

# Delete Cloud Build trigger
delete_cloud_build_trigger() {
    print_info "Deleting Cloud Build trigger..."
    
    if gcloud builds triggers describe "$TRIGGER_NAME" \
        --project="$PROJECT_ID" \
        --quiet >/dev/null 2>&1; then
        print_info "Deleting Cloud Build trigger: $TRIGGER_NAME"
        gcloud builds triggers delete "$TRIGGER_NAME" \
            --project="$PROJECT_ID" \
            --quiet || print_warning "Failed to delete trigger"
    else
        print_info "Cloud Build trigger $TRIGGER_NAME does not exist, skipping..."
    fi
    
    print_success "Cloud Build trigger cleanup completed"
}

# Remove IAM policy bindings
remove_iam_bindings() {
    print_info "Removing IAM policy bindings..."
    
    CLOUD_BUILD_SA="${PROJECT_ID}@cloudbuild.gserviceaccount.com"
    SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Remove Cloud Build service account permissions
    print_info "Removing Cloud Build service account permissions..."
    
    # Remove Artifact Registry writer
    gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${CLOUD_BUILD_SA}" \
        --role="roles/artifactregistry.writer" \
        --quiet >/dev/null 2>&1 || true
    
    # Remove Cloud Run admin
    gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${CLOUD_BUILD_SA}" \
        --role="roles/run.admin" \
        --quiet >/dev/null 2>&1 || true
    
    # Remove Cloud Deploy releaser
    gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${CLOUD_BUILD_SA}" \
        --role="roles/clouddeploy.releaser" \
        --quiet >/dev/null 2>&1 || true
    
    # Remove Cloud Deploy job runner
    gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${CLOUD_BUILD_SA}" \
        --role="roles/clouddeploy.jobRunner" \
        --quiet >/dev/null 2>&1 || true
    
    # Remove service account user role from Cloud Build
    gcloud iam service-accounts remove-iam-policy-binding \
        "$SERVICE_ACCOUNT_EMAIL" \
        --member="serviceAccount:${CLOUD_BUILD_SA}" \
        --role="roles/iam.serviceAccountUser" \
        --project="$PROJECT_ID" \
        --quiet >/dev/null 2>&1 || true
    
    # Remove Cloud Run invoker from service account
    gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
        --role="roles/run.invoker" \
        --quiet >/dev/null 2>&1 || true
    
    print_success "IAM policy bindings removed"
}

# Delete service account
delete_service_account() {
    print_info "Deleting service account..."
    
    SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if gcloud iam service-accounts describe "$SERVICE_ACCOUNT_EMAIL" \
        --project="$PROJECT_ID" \
        --quiet >/dev/null 2>&1; then
        print_info "Deleting service account: $SERVICE_ACCOUNT_EMAIL"
        gcloud iam service-accounts delete "$SERVICE_ACCOUNT_EMAIL" \
            --project="$PROJECT_ID" \
            --quiet || print_warning "Failed to delete service account"
    else
        print_info "Service account $SERVICE_ACCOUNT_EMAIL does not exist, skipping..."
    fi
    
    print_success "Service account cleanup completed"
}

# Print summary
print_summary() {
    echo
    print_success "========================================="
    print_success "Cleanup completed!"
    print_success "========================================="
    echo
    print_info "All resources have been deleted:"
    echo "  ✓ Cloud Deploy pipeline and targets"
    echo "  ✓ Cloud Run services"
    echo "  ✓ Artifact Registry repository"
    echo "  ✓ Service account"
    echo "  ✓ Cloud Build trigger"
    echo "  ✓ IAM policy bindings"
    echo
    print_warning "Note: Some IAM bindings may require manual cleanup if they were shared with other resources"
    echo
}

# Main execution
main() {
    echo
    print_info "========================================="
    print_info "Order API CI/CD Pipeline Cleanup"
    print_info "========================================="
    echo
    
    check_prerequisites
    get_project_id
    confirm_deletion
    
    # Order matters: delete resources before removing IAM bindings
    delete_cloud_run_services
    delete_cloud_deploy
    delete_cloud_build_trigger
    delete_artifact_registry
    remove_iam_bindings
    delete_service_account
    
    print_summary
}

# Run main function
main

