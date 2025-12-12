param (
    [string]$ClusterName
)

Write-Host "Creating Kind cluster '$ClusterName'..."

if ((kind get clusters) -like "$ClusterName") {
    Write-Host "⚠ Cluster '$ClusterName' already exists"
} else {
    # Check if kind-config.yaml exists before trying to use it
    if (Test-Path "kind-config.yaml") {
        kind create cluster --name $ClusterName --config kind-config.yaml
        Write-Host "✓ Cluster created with config"
    } else {
        kind create cluster --name $ClusterName
        Write-Host "✓ Cluster created without config (kind-config.yaml not found)"
    }
}
