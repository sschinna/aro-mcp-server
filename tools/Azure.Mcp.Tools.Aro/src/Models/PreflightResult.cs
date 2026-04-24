// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

namespace Azure.Mcp.Tools.Aro.Models;

public class PreflightResult
{
    public string? Location { get; set; }
    public bool MasterVmAvailable { get; set; }
    public bool WorkerVmAvailable { get; set; }
    public string? MasterVmSize { get; set; }
    public string? WorkerVmSize { get; set; }
    public string? MasterVmRestriction { get; set; }
    public string? WorkerVmRestriction { get; set; }
    public List<string>? AvailableVersions { get; set; }
    public string? MatchedVersion { get; set; }
    public bool IsEligible { get; set; }
    public string? Summary { get; set; }
}
