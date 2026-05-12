[CmdletBinding()]
param(
    [string]$Owner = 'HomeAssistantFork',

    [string]$Repo = 'gentoo_home_assistant_build_pipeline',

    [string]$WorkflowName = 'Build GentooHA',

    [string]$Branch = 'emerge_path',

    [string]$Platform = 'x64',

    [string]$Flavor = 'debug',

    [Nullable[long]]$RunId,

    [int]$PollMinutes = 5,

    [int]$MaxPolls = 0,

    [switch]$DispatchWorkflow,

    [switch]$ReusePreviousArtifacts,

    [switch]$ReuseBinpkgBundle,

    [string]$ReuseSourceRunId,

    [switch]$InvokeCopilotOnFailure,

    [switch]$CopilotYolo,

    [switch]$UsePrereleaseCopilot,

    [string]$CopilotModel = 'GPT-5.4',

    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path,

    [string]$LogRoot = (Join-Path $PSScriptRoot 'logs')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-GitHubApi {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$Raw
    )

    $output = & gh api @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "gh api failed: $($Arguments -join ' ')"
    }

    if ($Raw) {
        return $output
    }

    if ([string]::IsNullOrWhiteSpace(($output | Out-String))) {
        return $null
    }

    return $output | ConvertFrom-Json
}

function Get-WorkflowId {
    $workflows = Invoke-GitHubApi -Arguments @("repos/$Owner/$Repo/actions/workflows")
    $workflow = $workflows.workflows | Where-Object {
        $_.name -eq $WorkflowName -or $_.path -eq $WorkflowName
    } | Select-Object -First 1

    if (-not $workflow) {
        throw "Workflow not found: $WorkflowName"
    }

    return [long]$workflow.id
}

function Get-LatestRun {
    $runs = Invoke-GitHubApi -Arguments @("repos/$Owner/$Repo/actions/runs?per_page=50")
    $matchingRuns = $runs.workflow_runs | Where-Object {
        $_.name -eq $WorkflowName -and $_.head_branch -eq $Branch
    } | Sort-Object created_at -Descending

    return $matchingRuns | Select-Object -First 1
}

function Get-Run {
    param([Parameter(Mandatory = $true)][long]$Id)
    return Invoke-GitHubApi -Arguments @("repos/$Owner/$Repo/actions/runs/$Id")
}

function Get-RunJobs {
    param([Parameter(Mandatory = $true)][long]$Id)
    $jobsResponse = Invoke-GitHubApi -Arguments @("repos/$Owner/$Repo/actions/runs/$Id/jobs?per_page=100")
    return @($jobsResponse.jobs)
}

function Resolve-CopilotCommand {
    $command = Get-Command copilot -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    if (Test-Command -Name npm) {
        $npmPrefix = (npm prefix -g).Trim()
        foreach ($candidate in @(
            (Join-Path $npmPrefix 'copilot.cmd'),
            (Join-Path $npmPrefix 'copilot'),
            (Join-Path $npmPrefix 'node_modules\.bin\copilot.cmd'),
            (Join-Path $npmPrefix 'node_modules\.bin\copilot')
        )) {
            if (Test-Path -LiteralPath $candidate) {
                return $candidate
            }
        }
    }

    return $null
}

function Save-RunSnapshot {
    param(
        [Parameter(Mandatory = $true)]$Run,
        [Parameter(Mandatory = $true)][array]$Jobs,
        [Parameter(Mandatory = $true)][string]$Directory
    )

    $snapshot = [ordered]@{
        captured_at = (Get-Date).ToString('o')
        run         = $Run
        jobs        = $Jobs
    }

    $jsonPath = Join-Path $Directory 'latest-status.json'
    $textPath = Join-Path $Directory 'latest-status.txt'

    $snapshot | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $lines = @(
        "captured_at=$($snapshot.captured_at)",
        "run_id=$($Run.id)",
        "status=$($Run.status)",
        "conclusion=$($Run.conclusion)",
        "html_url=$($Run.html_url)",
        ''
    )

    foreach ($job in $Jobs) {
        $lines += "{0}`t{1}`t{2}" -f $job.name, $job.status, $job.conclusion
    }

    $lines | Set-Content -LiteralPath $textPath -Encoding UTF8
}

function Export-FailedJobLog {
    param(
        [Parameter(Mandatory = $true)][long]$WorkflowRunId,
        [Parameter(Mandatory = $true)][long]$JobId,
        [Parameter(Mandatory = $true)][string]$OutputPath
    )

    $logText = & gh run view $WorkflowRunId --job $JobId --log-failed
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to retrieve log for run $WorkflowRunId job $JobId"
    }

    $logText | Set-Content -LiteralPath $OutputPath -Encoding UTF8
}

function Start-CopilotInvestigation {
    param(
        [Parameter(Mandatory = $true)][long]$WorkflowRunId,
        [Parameter(Mandatory = $true)][string]$FailureReason,
        [Parameter(Mandatory = $true)][string]$LogDirectory,
        [string]$AttachmentPath
    )

    $copilotCommand = Resolve-CopilotCommand
    if (-not $copilotCommand) {
        throw 'copilot command not found. Install GitHub Copilot CLI and log in before using -InvokeCopilotOnFailure.'
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $copilotStdout = Join-Path $LogDirectory "copilot_$timestamp.stdout.jsonl"
    $copilotStderr = Join-Path $LogDirectory "copilot_$timestamp.stderr.log"
    $promptPath = Join-Path $LogDirectory "copilot_$timestamp.prompt.txt"

    $prompt = @"
Investigate GitHub Actions workflow failure in the local repository at $RepoRoot.

Repository: $Owner/$Repo
Workflow: $WorkflowName
Run ID: $WorkflowRunId
Branch: $Branch
Platform: $Platform
Flavor: $Flavor
Failure reason: $FailureReason

Requirements:
1. Read the attached workflow log if present.
2. Inspect the local repository and identify the root cause of the failure.
3. Make the smallest safe fix in the repo if the cause is clear.
4. Run the narrowest validation available for the touched code.
5. Summarize the result, including any remaining blocker.
"@

    $prompt | Set-Content -LiteralPath $promptPath -Encoding UTF8

    $arguments = @(
        '--experimental',
        '--autopilot',
        '--prompt', $prompt,
        '--output-format', 'json',
        '--model', $CopilotModel
    )

    if ($CopilotYolo) {
        $arguments += '--yolo'
    }

    if ($AttachmentPath -and (Test-Path -LiteralPath $AttachmentPath)) {
        $arguments += '--attachment'
        $arguments += $AttachmentPath
    }

    $process = Start-Process -FilePath $copilotCommand -ArgumentList $arguments -WorkingDirectory $RepoRoot -RedirectStandardOutput $copilotStdout -RedirectStandardError $copilotStderr -PassThru

    [ordered]@{
        started_at = (Get-Date).ToString('o')
        pid        = $process.Id
        stdout     = $copilotStdout
        stderr     = $copilotStderr
        prompt     = $promptPath
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $LogDirectory 'active-copilot-run.json') -Encoding UTF8

    Write-Host "Started copilot PID $($process.Id)"
    Write-Host "stdout: $copilotStdout"
    Write-Host "stderr: $copilotStderr"
}

if (-not (Test-Command -Name gh)) {
    throw 'gh CLI is required.'
}

New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
$watchDirectory = Join-Path $LogRoot (Get-Date -Format 'yyyyMMdd_HHmmss')
New-Item -ItemType Directory -Path $watchDirectory -Force | Out-Null

if ($DispatchWorkflow) {
    $workflowId = Get-WorkflowId
    $dispatchArgs = @(
        "repos/$Owner/$Repo/actions/workflows/$workflowId/dispatches",
        '--method', 'POST',
        '-f', "ref=$Branch",
        '-f', "inputs[platform]=$Platform",
        '-f', "inputs[flavor]=$Flavor"
    )

    if ($ReusePreviousArtifacts) {
        $dispatchArgs += @('-f', 'inputs[reuse_previous_artifacts]=true')
    }

    if ($ReuseBinpkgBundle) {
        $dispatchArgs += @('-f', 'inputs[reuse_binpkg_bundle]=true')
    }

    if (-not [string]::IsNullOrWhiteSpace($ReuseSourceRunId)) {
        $dispatchArgs += @('-f', "inputs[reuse_source_run_id]=$ReuseSourceRunId")
    }

    & gh api @dispatchArgs
    if ($LASTEXITCODE -ne 0) {
        throw 'Workflow dispatch failed.'
    }

    Start-Sleep -Seconds 5
}

if (-not $RunId) {
    $latestRun = Get-LatestRun
    if (-not $latestRun) {
        throw "No workflow runs found for $WorkflowName on branch $Branch"
    }

    $RunId = [long]$latestRun.id
}

Write-Host "Watching run $RunId"
Write-Host "Logs: $watchDirectory"

$copilotTriggered = $false
$pollCount = 0
$previousState = $null

while ($true) {
    $pollCount += 1

    $run = Get-Run -Id $RunId
    $jobs = Get-RunJobs -Id $RunId
    Save-RunSnapshot -Run $run -Jobs $jobs -Directory $watchDirectory

    $state = "$($run.status)|$($run.conclusion)"
    if ($state -ne $previousState) {
        Write-Host ("[{0}] run {1}: {2} / {3}" -f (Get-Date -Format 's'), $RunId, $run.status, $run.conclusion)
        $previousState = $state
    }

    $failedJob = $jobs | Where-Object {
        $_.conclusion -eq 'failure'
    } | Sort-Object started_at, name | Select-Object -First 1

    if ($InvokeCopilotOnFailure -and -not $copilotTriggered) {
        $shouldTrigger = $false
        $failureReason = $null
        $attachmentPath = $null

        if ($failedJob) {
            $shouldTrigger = $true
            $failureReason = "job failed: $($failedJob.name)"
        }
        elseif ($run.status -eq 'completed' -and $run.conclusion -eq 'failure') {
            $shouldTrigger = $true
            $failureReason = 'workflow completed with failure'
        }

        if ($shouldTrigger) {
            if ($failedJob) {
                $safeJobName = ($failedJob.name -replace '[^A-Za-z0-9._-]+', '_').Trim('_')
                if ([string]::IsNullOrWhiteSpace($safeJobName)) {
                    $safeJobName = 'failed-job'
                }
                $attachmentPath = Join-Path $watchDirectory "$safeJobName.failed.log"
                try {
                    Export-FailedJobLog -WorkflowRunId $RunId -JobId ([long]$failedJob.id) -OutputPath $attachmentPath
                }
                catch {
                    $attachmentPath = $null
                }
            }

            Start-CopilotInvestigation -WorkflowRunId $RunId -FailureReason $failureReason -LogDirectory $watchDirectory -AttachmentPath $attachmentPath
            $copilotTriggered = $true
        }
    }

    if ($run.status -eq 'completed') {
        Write-Host "Run $RunId completed with conclusion: $($run.conclusion)"
        break
    }

    if ($MaxPolls -gt 0 -and $pollCount -ge $MaxPolls) {
        Write-Host "Reached MaxPolls=$MaxPolls"
        break
    }

    Start-Sleep -Seconds ($PollMinutes * 60)
}