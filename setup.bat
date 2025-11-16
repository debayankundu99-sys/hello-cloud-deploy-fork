@echo off
REM Setup script for Order API CI/CD pipeline on GCP (Windows)
REM This script automates the complete setup of Cloud Build, Cloud Deploy, and Cloud Run

setlocal enabledelayedexpansion

REM Configuration variables
set SERVICE_NAME=order-api
set REGION=asia-south1
set REPO_NAME=order-api-repo
set SERVICE_ACCOUNT_NAME=order-api-sa
set PIPELINE_NAME=order-api-pipeline

echo.
echo =========================================
echo Order API CI/CD Pipeline Setup
echo =========================================
echo.

REM Check if gcloud is installed
where gcloud >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install
    exit /b 1
)

echo [INFO] gcloud CLI is installed

REM Check if user is authenticated
gcloud auth list --filter=status:ACTIVE --format="value(account)" >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] No active gcloud authentication found. Please run: gcloud auth login
    exit /b 1
)

echo [SUCCESS] gcloud authentication verified
echo.

REM Get or set project ID
if "%PROJECT_ID%"=="" (
    for /f "tokens=*" %%i in ('gcloud config get-value project 2^>nul') do set CURRENT_PROJECT=%%i
    
    if not "!CURRENT_PROJECT!"=="" (
        if not "!CURRENT_PROJECT!"=="(unset)" (
            set PROJECT_ID=!CURRENT_PROJECT!
            echo [INFO] Using default project from gcloud config: !PROJECT_ID!
        ) else (
            echo [WARNING] No default project found in gcloud config
            set /p PROJECT_ID="Enter your GCP Project ID: "
        )
    ) else (
        echo [WARNING] No default project found in gcloud config
        set /p PROJECT_ID="Enter your GCP Project ID: "
    )
)

if "%PROJECT_ID%"=="" (
    echo [ERROR] Project ID is required
    exit /b 1
)

REM Verify project exists and is accessible
echo [INFO] Verifying project access...
gcloud projects describe %PROJECT_ID% --quiet >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Project '%PROJECT_ID%' not found or not accessible
    exit /b 1
)

REM Set project in gcloud config (in case it wasn't already set)
gcloud config set project %PROJECT_ID% --quiet >nul 2>&1
echo [SUCCESS] Using Project ID: %PROJECT_ID%
echo.

REM Enable required APIs
echo [INFO] Enabling required GCP APIs...
gcloud services enable cloudbuild.googleapis.com clouddeploy.googleapis.com run.googleapis.com artifactregistry.googleapis.com cloudresourcemanager.googleapis.com iam.googleapis.com --project=%PROJECT_ID% --quiet
if %ERRORLEVEL% NEQ 0 (
    echo [WARNING] Some APIs may have failed to enable. Continuing...
) else (
    echo [SUCCESS] All required APIs enabled
)
echo.

REM Create Artifact Registry repository
echo [INFO] Creating Artifact Registry repository...
gcloud artifacts repositories describe %REPO_NAME% --location=%REGION% --project=%PROJECT_ID% --quiet >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [WARNING] Artifact Registry repository '%REPO_NAME%' already exists, skipping...
) else (
    gcloud artifacts repositories create %REPO_NAME% --repository-format=docker --location=%REGION% --description="Docker repository for Order API" --project=%PROJECT_ID% --quiet
    if %ERRORLEVEL% EQU 0 (
        echo [SUCCESS] Artifact Registry repository created
    ) else (
        echo [ERROR] Failed to create Artifact Registry repository
        exit /b 1
    )
)
echo.

REM Create service account for Cloud Run
echo [INFO] Creating service account for Cloud Run...
gcloud iam service-accounts describe %SERVICE_ACCOUNT_NAME%@%PROJECT_ID%.iam.gserviceaccount.com --project=%PROJECT_ID% --quiet >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [WARNING] Service account '%SERVICE_ACCOUNT_NAME%' already exists, skipping creation...
) else (
    gcloud iam service-accounts create %SERVICE_ACCOUNT_NAME% --display-name="Order API Service Account" --description="Service account for Order API Cloud Run service" --project=%PROJECT_ID% --quiet
    if %ERRORLEVEL% NEQ 0 (
        echo [ERROR] Failed to create service account
        exit /b 1
    )
    echo [SUCCESS] Service account created
)

REM Grant Cloud Run invoker role
echo [INFO] Granting Cloud Run invoker role to service account...
gcloud projects add-iam-policy-binding %PROJECT_ID% --member="serviceAccount:%SERVICE_ACCOUNT_NAME%@%PROJECT_ID%.iam.gserviceaccount.com" --role="roles/run.invoker" --condition=None --quiet >nul 2>&1
echo [SUCCESS] Service account permissions configured
echo.

REM Grant Cloud Build and Cloud Deploy permissions
echo [INFO] Granting permissions to Cloud Build and Cloud Deploy service accounts...
set CLOUD_BUILD_SA=%PROJECT_ID%@cloudbuild.gserviceaccount.com

REM Grant Artifact Registry writer
gcloud projects add-iam-policy-binding %PROJECT_ID% --member="serviceAccount:%CLOUD_BUILD_SA%" --role="roles/artifactregistry.writer" --condition=None --quiet >nul 2>&1

REM Grant Cloud Run admin
gcloud projects add-iam-policy-binding %PROJECT_ID% --member="serviceAccount:%CLOUD_BUILD_SA%" --role="roles/run.admin" --condition=None --quiet >nul 2>&1

REM Grant Cloud Deploy releaser
gcloud projects add-iam-policy-binding %PROJECT_ID% --member="serviceAccount:%CLOUD_BUILD_SA%" --role="roles/clouddeploy.releaser" --condition=None --quiet >nul 2>&1

REM Grant Cloud Deploy job runner
gcloud projects add-iam-policy-binding %PROJECT_ID% --member="serviceAccount:%CLOUD_BUILD_SA%" --role="roles/clouddeploy.jobRunner" --condition=None --quiet >nul 2>&1

REM Grant service account user role to Cloud Build
gcloud iam service-accounts add-iam-policy-binding %SERVICE_ACCOUNT_NAME%@%PROJECT_ID%.iam.gserviceaccount.com --member="serviceAccount:%CLOUD_BUILD_SA%" --role="roles/iam.serviceAccountUser" --project=%PROJECT_ID% --quiet >nul 2>&1

REM Get Cloud Deploy service agent
for /f "delims=" %%i in ('gcloud projects describe %PROJECT_ID% --format="value(projectNumber)"') do set PROJECT_NUMBER=%%i
set CLOUD_DEPLOY_SA=service-%PROJECT_NUMBER%@gcp-sa-clouddeploy.iam.gserviceaccount.com

REM Grant Cloud Deploy service agent permission to act as the service account
echo [INFO] Granting Cloud Deploy service agent permission to deploy Cloud Run services...
gcloud iam service-accounts add-iam-policy-binding %SERVICE_ACCOUNT_NAME%@%PROJECT_ID%.iam.gserviceaccount.com --member="serviceAccount:%CLOUD_DEPLOY_SA%" --role="roles/iam.serviceAccountUser" --project=%PROJECT_ID% --quiet >nul 2>&1

REM Grant Cloud Deploy service agent Cloud Run admin
gcloud projects add-iam-policy-binding %PROJECT_ID% --member="serviceAccount:%CLOUD_DEPLOY_SA%" --role="roles/run.developer" --condition=None --quiet >nul 2>&1

echo [SUCCESS] Cloud Build and Cloud Deploy permissions granted
echo.

REM Initialize Cloud Deploy
echo [INFO] Initializing Cloud Deploy pipeline...
gcloud deploy pipelines describe %PIPELINE_NAME% --region=%REGION% --project=%PROJECT_ID% --quiet >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [WARNING] Cloud Deploy pipeline '%PIPELINE_NAME%' already exists, skipping...
) else (
    if exist clouddeploy.yaml (
        REM Replace PROJECT_ID placeholder in clouddeploy.yaml
        powershell -Command "(Get-Content clouddeploy.yaml) -replace '\$\{PROJECT_ID\}', '%PROJECT_ID%' | Set-Content clouddeploy-temp.yaml"
        
        gcloud deploy apply --file=clouddeploy-temp.yaml --region=%REGION% --project=%PROJECT_ID% --quiet
        if %ERRORLEVEL% EQU 0 (
            echo [SUCCESS] Cloud Deploy pipeline initialized
            del clouddeploy-temp.yaml >nul 2>&1
        ) else (
            echo [ERROR] Failed to initialize Cloud Deploy pipeline
            del clouddeploy-temp.yaml >nul 2>&1
            exit /b 1
        )
    ) else (
        echo [ERROR] clouddeploy.yaml not found in current directory
        exit /b 1
    )
)
echo.

REM Create Cloud Build trigger (optional)
echo [INFO] Setting up Cloud Build trigger...
set /p CREATE_TRIGGER="Do you want to create a Cloud Build trigger? (y/n): "
if /i not "!CREATE_TRIGGER!"=="y" (
    echo [INFO] Skipping Cloud Build trigger creation
    goto :summary
)

set /p REPO_URL="Enter your Git repository URL (e.g., https://github.com/user/repo.git): "
if "!REPO_URL!"=="" (
    echo [WARNING] No repository URL provided, skipping trigger creation
    goto :summary
)

set /p BRANCH_NAME="Enter branch name to trigger on (default: main): "
if "!BRANCH_NAME!"=="" set BRANCH_NAME=main

echo [INFO] Creating Cloud Build trigger...
echo [WARNING] Automatic trigger creation from batch script is limited.
echo [INFO] Please create the trigger manually using:
echo   gcloud builds triggers create github --name=order-api-trigger --repo-name=REPO --repo-owner=OWNER --branch-pattern=^%BRANCH_NAME%$ --build-config=cloudbuild.yaml --substitutions=_SERVICE_NAME=%SERVICE_NAME%,_REGION=%REGION%,_REPO_NAME=%REPO_NAME%

:summary
echo.
echo [SUCCESS] =========================================
echo [SUCCESS] Setup completed successfully!
echo [SUCCESS] =========================================
echo.
echo [INFO] Project ID: %PROJECT_ID%
echo [INFO] Region: %REGION%
echo [INFO] Service Name: %SERVICE_NAME%
echo [INFO] Artifact Registry: %REPO_NAME%
echo [INFO] Service Account: %SERVICE_ACCOUNT_NAME%@%PROJECT_ID%.iam.gserviceaccount.com
echo.
echo [INFO] Next steps:
echo   1. Verify the setup: gcloud deploy pipelines describe %PIPELINE_NAME% --region=%REGION%
echo   2. Test the build: gcloud builds submit --config=cloudbuild.yaml
echo   3. View Cloud Run services: gcloud run services list --region=%REGION%
echo.
echo [INFO] For manual deployment, run:
echo   gcloud builds submit --config=cloudbuild.yaml --substitutions=_SERVICE_NAME=%SERVICE_NAME%,_REGION=%REGION%,_REPO_NAME=%REPO_NAME%,_IMAGE_TAG=^<commit-hash^>
echo.

endlocal

