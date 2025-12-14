param (
    [string]$ModelName,
    [string]$Namespace
)

Write-Host "Deploying model to Kubernetes..."
Write-Host "v Model files are embedded in the Docker image"

# Apply the SeldonDeployment manifest
kubectl apply -f k8s/seldon-deployment.yaml
if ($LASTEXITCODE -ne 0) {
    Write-Host "x Failed to apply SeldonDeployment manifest."
    exit 1
}
Write-Host "v SeldonDeployment created"

# Ensure Seldon Core operator is ready
Write-Host "Ensuring Seldon Core operator is ready in seldon-system namespace..."
kubectl wait --for=condition=available --timeout=300s deployment/seldon-controller-manager -n seldon-system
if ($LASTEXITCODE -ne 0) {
    Write-Host "x Seldon Core operator is not ready. Please check 'make install-seldon' or 'kubectl get pods -n seldon-system'."
    exit 1
}
Write-Host "v Seldon Core operator is ready."

Write-Host "Waiting for deployment to be ready..."
kubectl wait --for=condition=ready pod `
    -l app=$ModelName-default-0-classifier `
    --namespace=$Namespace `
    --timeout=300s

if ($LASTEXITCODE -ne 0) {
    Write-Host "x Deployment wait timed out or failed. Running debug information..."
    Write-Host "================================================================"
    Write-Host "  DEPLOYMENT DEBUG INFORMATION"
    Write-Host "================================================================"
    Write-Host ""

    # Attempt to get the name of any pod belonging to our model deployment
    $podName = kubectl get pod -l app=$ModelName-default-0-classifier -o jsonpath='{.items[0].metadata.name}' 2>$null

    if ($podName) {
        Write-Host "Found pod: $podName"
        Write-Host ""
        Write-Host "--- Pod Description ---"
        kubectl describe pod $podName
        Write-Host ""
        Write-Host "--- Pod Logs (classifier container) ---"
        kubectl logs $podName -c classifier
        Write-Host ""
        Write-Host "--- Pod Logs (seldon-container-engine) ---"
        kubectl logs $podName -c seldon-container-engine
    } else {
        Write-Host "No pods found with label app=$ModelName-default-0-classifier. Showing all pods in namespace:"
        kubectl get pods -n $Namespace
    }
    Write-Host "================================================================"
    exit 1 # Indicate failure to the calling process
}

Write-Host ""
Write-Host "v Deployment complete!"
Write-Host ""

# Call make status indirectly. We can't directly call make status here
# but the Makefile still has a status target.
# Consider if you want to explicitly output status info from within this script
# or rely on a subsequent 'make status' command.
# For now, let's keep it simple and expect the user to run 'make status' if needed.

# Alternatively, if you want status to be part of the script, you would do:
# kubectl get seldondeployment $ModelName -o wide
# kubectl get pods -l app=$ModelName-default-0-classifier -o wide
# kubectl get svc -l app=$ModelName

exit 0 # Indicate success
