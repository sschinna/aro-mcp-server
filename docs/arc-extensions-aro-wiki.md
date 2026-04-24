# Adding Azure Arc Extensions to ARO Clusters

> **Internal Wiki** — Azure Red Hat OpenShift (ARO) + Azure Arc-enabled Kubernetes

## Overview

Azure Red Hat OpenShift (ARO) does **not** have native support for Azure extensions like AKS does. To enable services such as Microsoft Defender for Containers, Azure Policy, Azure Monitor, or GitOps on ARO, you must first **Arc-enable** the cluster, then install extensions on top of the Arc agent.

**Architecture:**

```
ARO Cluster (OpenShift 4.x)
  └── Azure Arc Agent (azure-arc namespace)
        ├── Defender Extension (mdc namespace)
        ├── Azure Policy Extension (optional)
        ├── Azure Monitor Extension (optional)
        └── GitOps / Flux Extension (optional)
```

---

## Prerequisites

| Requirement | Details |
|---|---|
| ARO cluster | Running, version 4.14+ recommended |
| `oc` CLI | Logged in with `kubeadmin` or cluster-admin privileges |
| `az` CLI | v2.50+ with `connectedk8s` and `k8s-extension` extensions |
| Subscription access | Owner or Contributor + User Access Administrator |
| Resource providers | `Microsoft.Kubernetes`, `Microsoft.KubernetesConfiguration`, `Microsoft.ExtendedLocation` |

### Install required CLI extensions

```bash
az extension add --name connectedk8s --upgrade
az extension add --name k8s-extension --upgrade
```

### Register resource providers

```bash
az provider register --namespace Microsoft.Kubernetes --wait
az provider register --namespace Microsoft.KubernetesConfiguration --wait
az provider register --namespace Microsoft.ExtendedLocation --wait
```

Verify registration:

```bash
az provider show -n Microsoft.Kubernetes --query "registrationState" -o tsv
# Expected: Registered
```

---

## Step 1: Log in to the ARO Cluster

Get credentials and log in via `oc`:

```bash
# Get API server URL and kubeadmin password
RESOURCE_GROUP="<your-rg>"
CLUSTER_NAME="<your-aro-cluster>"

API_SERVER=$(az aro show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query "apiserverProfile.url" -o tsv)
KUBEADMIN_PASS=$(az aro list-credentials -g $RESOURCE_GROUP -n $CLUSTER_NAME --query "kubeadminPassword" -o tsv)

oc login $API_SERVER -u kubeadmin -p $KUBEADMIN_PASS
```

Verify access:

```bash
oc get nodes
oc get clusterversion
```

---

## Step 2: Arc-enable the ARO Cluster

Connect the cluster to Azure Arc:

```bash
az connectedk8s connect \
  --name $CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --location <azure-region> \
  --distribution openshift
```

> **Important:** The `--distribution openshift` flag is required for ARO. Without it, the Arc agent may not configure correctly for OpenShift's security context constraints (SCCs).

This takes 2-5 minutes. Verify:

```bash
az connectedk8s show \
  --name $CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "{name:name, connectivityStatus:connectivityStatus, distribution:distribution, infrastructure:infrastructure}" \
  -o table
```

Expected output:

```
Name                  ConnectivityStatus    Distribution    Infrastructure
--------------------  --------------------  --------------  ----------------
aro-defender-cluster  Connected             openshift       azure
```

Also confirm the Arc pods are running:

```bash
oc get pods -n azure-arc
```

---

## Step 3: Install Arc Extensions

### 3a. Microsoft Defender for Containers

**Pre-requisite:** Enable Defender for Containers at the subscription level:

```bash
az security pricing create --name Containers --tier Standard
```

Verify:

```bash
az security pricing show --name Containers --query "pricingTier" -o tsv
# Expected: Standard
```

**Install the Defender extension:**

```bash
az k8s-extension create \
  --name microsoft.azuredefender.kubernetes \
  --cluster-name $CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --cluster-type connectedClusters \
  --extension-type microsoft.azuredefender.kubernetes \
  --configuration-settings "auditLogPath=/var/log/kube-apiserver/audit.log"
```

> **Note:** ARO audit log path is `/var/log/kube-apiserver/audit.log`. This differs from vanilla Kubernetes.

Verify installation:

```bash
az k8s-extension show \
  --name microsoft.azuredefender.kubernetes \
  --cluster-name $CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --cluster-type connectedClusters \
  --query "{name:name, type:extensionType, state:provisioningState, version:currentVersion, namespace:scope.cluster.releaseNamespace}" \
  -o table
```

Verify pods are running:

```bash
oc get pods -n mdc
```

Expected: 13 pods (6 collectors, 6 publishers, 1 pod-collector-misc) across all nodes.

```
NAME                                         READY   STATUS    RESTARTS
microsoft-defender-collector-ds-xxxxx        1/1     Running   0
microsoft-defender-publisher-ds-xxxxx        1/1     Running   0
microsoft-defender-pod-collector-misc-xxxxx  1/1     Running   0
...
```

---

### 3b. Azure Policy (Optional)

```bash
az k8s-extension create \
  --name azurepolicy \
  --cluster-name $CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --cluster-type connectedClusters \
  --extension-type Microsoft.PolicyInsights
```

---

### 3c. Azure Monitor / Container Insights (Optional)

```bash
# Create or reference an existing Log Analytics workspace
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group <workspace-rg> \
  --workspace-name <workspace-name> \
  --query "id" -o tsv)

az k8s-extension create \
  --name azuremonitor-containers \
  --cluster-name $CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --cluster-type connectedClusters \
  --extension-type Microsoft.AzureMonitor.Containers \
  --configuration-settings "logAnalyticsWorkspaceResourceID=$WORKSPACE_ID"
```

---

### 3d. GitOps / Flux v2 (Optional)

```bash
az k8s-extension create \
  --name flux \
  --cluster-name $CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --cluster-type connectedClusters \
  --extension-type microsoft.flux
```

---

## Managing Extensions

### List all extensions on a cluster

```bash
az k8s-extension list \
  --cluster-name $CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --cluster-type connectedClusters \
  -o table
```

### Update an extension

```bash
az k8s-extension update \
  --name microsoft.azuredefender.kubernetes \
  --cluster-name $CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --cluster-type connectedClusters \
  --configuration-settings "key=value"
```

### Delete an extension

```bash
az k8s-extension delete \
  --name microsoft.azuredefender.kubernetes \
  --cluster-name $CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --cluster-type connectedClusters \
  --yes
```

### Disconnect Arc (removes all extensions)

```bash
az connectedk8s delete \
  --name $CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --yes
```

---

## Removing Defender & Arc: Step-by-Step and Known Scenarios

Removing Defender and Arc from an ARO cluster is straightforward, but the **order of operations matters** and there are several side-effects to plan for.

### Correct Removal Order

> **Always delete extensions FIRST, then disconnect Arc.**
> If you disconnect Arc first, extensions become orphaned — they can't be cleanly removed via CLI and you'll need to manually clean up Helm releases and namespaces on the cluster.

```bash
# Step 1: Delete the Defender extension
az k8s-extension delete \
  --name microsoft.azuredefender.kubernetes \
  --cluster-name $CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --cluster-type connectedClusters \
  --yes

# Step 2: Verify extension is gone
az k8s-extension list \
  --cluster-name $CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --cluster-type connectedClusters \
  -o table

# Step 3: Disconnect Arc agent
az connectedk8s delete \
  --name $CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --yes

# Step 4: Verify cleanup
oc get ns azure-arc    # Should return NotFound
oc get ns mdc          # May still exist (empty shell)
az connectedk8s show --name $CLUSTER_NAME --resource-group $RESOURCE_GROUP
# Should return ResourceNotFound
```

### Post-Removal Verification

```bash
# Check for orphaned CRDs
oc get crd | grep -iE "arc|defender|microsoft"

# Check for orphaned ClusterRoleBindings
oc get clusterrolebinding | grep -iE "arc|defender|mdc"

# Check for leftover SCCs (OpenShift-specific)
oc get scc | grep -i arc

# Check for empty namespaces
oc get ns mdc azure-arc azure-arc-release 2>&1
```

### Scenario 1: Orphaned `mdc` Namespace

**What happens:** After deleting the Defender extension, the `mdc` namespace remains with `Active` status but zero pods. The extension delete removes workloads but does not always clean up the namespace.

**Impact:** Cosmetic only — no running workloads, no resource consumption.

**Fix:**

```bash
oc delete ns mdc
```

### Scenario 2: Subscription-Level Defender Plan Still Billing

**What happens:** Removing the extension from the cluster does **not** turn off the Defender for Containers plan at the subscription level. The `Containers=Standard` pricing tier remains active and continues to bill.

**Impact:** Ongoing charges for Defender for Containers subscription-level plan, even with no protected clusters.

**Fix:**

```bash
# Check current plan
az security pricing show --name Containers --query "pricingTier" -o tsv

# Downgrade to Free if no longer needed
az security pricing create --name Containers --tier Free
```

> **Warning:** Downgrading to Free affects **all** clusters in the subscription that rely on Defender for Containers, not just this one.

### Scenario 3: Orphaned Log Analytics Data

**What happens:** Defender sends security telemetry to a Log Analytics workspace (often auto-created as `DefaultWorkspace-<sub-id>-<region>`). Removing the extension stops new data flow but the **existing data remains** and incurs storage costs.

**Impact:** Storage costs for retained data in the Log Analytics workspace.

**Fix:**

```bash
# List workspaces
az monitor log-analytics workspace list --query "[].{name:name, rg:resourceGroup, retentionDays:retentionInDays}" -o table

# Optionally reduce retention or delete the workspace
az monitor log-analytics workspace delete \
  --resource-group DefaultResourceGroup-CUS \
  --workspace-name DefaultWorkspace-<sub-id>-CUS \
  --yes
```

### Scenario 4: Leftover CRDs and ClusterRoleBindings

**What happens:** Arc and Defender install Custom Resource Definitions and RBAC bindings at the cluster scope. These may not be fully cleaned up during uninstall.

**Impact:** Clutters `oc get crd` output; can conflict if you re-install later with a different version.

**Fix:**

```bash
# Delete Arc-related CRDs
oc get crd | grep -i arc | awk '{print $1}' | xargs oc delete crd

# Delete Arc-related ClusterRoleBindings
oc get clusterrolebinding | grep -iE "arc|defender|mdc" | awk '{print $1}' | xargs oc delete clusterrolebinding
```

### Scenario 5: Leftover OpenShift SCCs

**What happens:** Arc creates Security Context Constraints (SCCs) for its pods to run on OpenShift. These are not always removed on disconnect.

**Impact:** SCC accumulation; can cause naming conflicts on re-onboarding.

**Fix:**

```bash
oc get scc | grep -i arc
# If found:
oc delete scc <scc-name>
```

### Scenario 6: Disconnecting Arc Before Deleting Extensions

**What happens:** If you run `az connectedk8s delete` while extensions are still installed, the ARM-side extension resources are deleted, but the **in-cluster Helm releases and pods remain running** with no management plane.

**Impact:** Defender pods keep running but are unmanaged — they can't receive config updates, can't be deleted via CLI, and accumulate stale state.

**Fix:**

```bash
# Manually uninstall the orphaned Helm release
helm list -n mdc
helm uninstall <release-name> -n mdc

# Delete the namespace
oc delete ns mdc
```

### Scenario 7: Re-onboarding After Removal

**What happens:** If you re-connect the same cluster to Arc after removal, Azure creates a **new** connected cluster resource with a new resource ID.

**Impact:**
- Any Azure Policy assignments referencing the old resource ID must be re-applied
- Defender alert history is associated with the old resource — new resource starts fresh
- RBAC role assignments scoped to the old resource ID are invalid

**Fix:** After re-onboarding, re-apply all policy assignments, RBAC, and Defender exclusions to the new resource ID.

### Scenario 8: Immediate Security Coverage Gap

**What happens:** The moment Defender extension is deleted, the following protections stop:
- Container runtime threat detection
- Kubernetes audit log analysis
- Vulnerability assessment of running images
- Security alerts for the cluster

**Impact:** No new security alerts generated. Existing alerts in Defender for Cloud portal remain viewable but no active monitoring.

**Mitigation:** Plan the removal during a maintenance window and ensure an alternative monitoring solution is in place before removing.

### Scenario 9: No Impact on ARO Core

**What happens:** Removing Arc and Defender has **zero impact** on:
- ARO managed OpenShift components
- SRE access and cluster operations
- OpenShift console and API server
- Application workloads

**Why:** Arc and Defender run in isolated namespaces (`azure-arc`, `mdc`) and do not modify any ARO-managed resources. The ARO RP is completely independent of Arc.

---

## Troubleshooting

### Arc agent not connecting

```bash
# Check Arc agent logs
oc logs -n azure-arc -l app.kubernetes.io/component=connect-agent --tail=50

# Verify outbound connectivity (Arc requires HTTPS to Azure endpoints)
oc run test-curl --image=curlimages/curl --rm -it -- curl -s https://management.azure.com
```

### Defender pods not starting

```bash
# Check SCC (Security Context Constraints) — Arc creates its own
oc get scc | grep -i arc

# Check events in mdc namespace
oc get events -n mdc --sort-by='.lastTimestamp' | tail -20

# Describe a failing pod
oc describe pod -n mdc <pod-name>
```

### Extension stuck in "Creating" state

```bash
# Force delete and reinstall
az k8s-extension delete \
  --name microsoft.azuredefender.kubernetes \
  --cluster-name $CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --cluster-type connectedClusters \
  --yes --force

# Wait 2 minutes, then recreate
```

---

## ARO vs AKS: Key Differences for Arc Extensions

| Feature | AKS | ARO |
|---|---|---|
| Defender for Containers | Native addon (`--enable-defender`) | Requires Arc + extension |
| Azure Policy | Native addon (`--enable-addons azure-policy`) | Requires Arc + extension |
| Container Insights | Native addon (`--enable-addons monitoring`) | Requires Arc + extension |
| GitOps | Native or Arc | Requires Arc + extension |
| Arc agent required? | No (built-in) | **Yes** — always |
| Audit log path | `/var/log/kube-apiserver/audit.log` | `/var/log/kube-apiserver/audit.log` |
| SCC considerations | N/A (no SCCs) | Arc auto-creates SCCs |
| Managed identity for extensions | Native | Via Arc connected cluster identity |

---

## Verified Configuration (Reference Deployment)

This document was validated against:

| Component | Value |
|---|---|
| ARO Version | 4.20.15 |
| Region | centralus |
| Master VMs | Standard_D8s_v3 × 3 |
| Worker VMs | Standard_D4s_v3 × 3 |
| Arc connectivity | Connected, distribution=openshift |
| Defender extension | v0.8.50, namespace=mdc, 13 pods |
| Defender plan | Containers=Standard (subscription level) |
| Date verified | April 2026 |

---

## References

- [Azure Arc-enabled Kubernetes overview](https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/overview)
- [Connect an existing cluster to Azure Arc](https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/quickstart-connect-cluster)
- [Defender for Containers on Arc-enabled Kubernetes](https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-kubernetes-azure-arc)
- [ARO support policies](https://learn.microsoft.com/en-us/azure/openshift/support-policies-v4)
- [Azure Arc extensions list](https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/extensions-release)
