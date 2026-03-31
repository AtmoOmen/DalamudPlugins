param(
    [string]$PluginMasterPath = (Join-Path $PSScriptRoot "..\pluginmaster.json"),
    [string]$ConfigPath = (Join-Path $PSScriptRoot "..\.github\plugin-release-rules.json"),
    [string]$GitHubApiBase = "https://api.github.com"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:GitHubHeaders = @{
    Accept       = "application/vnd.github+json"
    "User-Agent" = "DalamudPlugins-PluginMaster-Updater"
}

if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
    $script:GitHubHeaders.Authorization = "Bearer $($env:GITHUB_TOKEN)"
}

$script:ReleaseCache = @{}

function Normalize-Version {
    param(
        [Parameter(Mandatory)]
        [string]$VersionText
    )

    $segments = $VersionText.Split(".", [StringSplitOptions]::RemoveEmptyEntries)
    if ($segments.Count -lt 3 -or $segments.Count -gt 4) {
        throw "不支持的版本号格式: $VersionText"
    }

    while ($segments.Count -lt 4) {
        $segments += "0"
    }

    return [string]::Join(".", $segments)
}

function ConvertTo-VersionObject {
    param(
        [Parameter(Mandatory)]
        [string]$VersionText
    )

    return [Version](Normalize-Version -VersionText $VersionText)
}

function Get-RepoSlugFromUrl {
    param(
        [Parameter(Mandatory)]
        [string]$RepoUrl
    )

    $match = [regex]::Match($RepoUrl, "^https://github\.com/(?<owner>[^/]+)/(?<repo>[^/?#]+?)(?:\.git)?/?$")
    if (-not $match.Success) {
        throw "无法从 RepoUrl 解析 GitHub 仓库: $RepoUrl"
    }

    return "$($match.Groups["owner"].Value)/$($match.Groups["repo"].Value)"
}

function Get-RuleLookup {
    param(
        [Parameter(Mandatory)]
        [array]$Rules
    )

    $lookup = @{}
    foreach ($rule in $Rules) {
        $internalName = [string]$rule.internalName
        if ([string]::IsNullOrWhiteSpace($internalName)) {
            throw "规则里存在空的 internalName"
        }

        if ($lookup.ContainsKey($internalName)) {
            throw "存在重复的规则 internalName: $internalName"
        }

        $lookup[$internalName] = $rule
    }

    return $lookup
}

function Get-Releases {
    param(
        [Parameter(Mandatory)]
        [string]$RepoSlug
    )

    if ($script:ReleaseCache.ContainsKey($RepoSlug)) {
        return $script:ReleaseCache[$RepoSlug]
    }

    $uri = "$GitHubApiBase/repos/$RepoSlug/releases?per_page=100"
    Write-Host "正在读取仓库 $RepoSlug 的 release 列表..."
    $releases = Invoke-RestMethod -Method Get -Headers $script:GitHubHeaders -Uri $uri
    $script:ReleaseCache[$RepoSlug] = @($releases)
    return $script:ReleaseCache[$RepoSlug]
}

function Get-LatestReleaseInfo {
    param(
        [Parameter(Mandatory)]
        [string]$RepoSlug,

        [string]$TagPrefix
    )

    if ([string]::IsNullOrWhiteSpace($TagPrefix)) {
        $normalizedPrefix = $null
    }
    else {
        $normalizedPrefix = $TagPrefix.Trim()
    }
    $tagPattern = if ($null -eq $normalizedPrefix) {
        "^(?<version>\d+\.\d+\.\d+(?:\.\d+)?)$"
    }
    else {
        "^{0}-(?<version>\d+\.\d+\.\d+(?:\.\d+)?)$" -f [regex]::Escape($normalizedPrefix)
    }

    $releases = Get-Releases -RepoSlug $RepoSlug
    $orderedReleases = $releases |
        Where-Object { -not $_.draft -and -not $_.prerelease } |
        Sort-Object {
            if ($_.published_at) {
                [DateTimeOffset]$_.published_at
            }
            elseif ($_.created_at) {
                [DateTimeOffset]$_.created_at
            }
            else {
                [DateTimeOffset]::MinValue
            }
        } -Descending

    foreach ($release in $orderedReleases) {
        $match = [regex]::Match([string]$release.tag_name, $tagPattern)
        if (-not $match.Success) {
            continue
        }

        return @{
            TagName          = [string]$release.tag_name
            AssemblyVersion  = Normalize-Version -VersionText $match.Groups["version"].Value
            PublishedAt      = [string]$release.published_at
        }
    }

    if ($null -eq $normalizedPrefix) {
        $modeDescription = "纯数字 Tag"
    }
    else {
        $modeDescription = "前缀为 $normalizedPrefix 的 Tag"
    }
    throw "仓库 $RepoSlug 中未找到符合条件的最新正式版 release: $modeDescription"
}

function Get-SelectedPluginIndexes {
    param(
        [Parameter(Mandatory)]
        [array]$Plugins
    )

    $selected = @{}
    for ($index = 0; $index -lt $Plugins.Count; $index++) {
        $plugin = $Plugins[$index]
        $internalName = [string]$plugin.InternalName
        if ([string]::IsNullOrWhiteSpace($internalName)) {
            throw "索引 $index 的插件缺少 InternalName"
        }

        $versionObject = ConvertTo-VersionObject -VersionText ([string]$plugin.AssemblyVersion)
        if (-not $selected.ContainsKey($internalName) -or $versionObject -gt $selected[$internalName].Version) {
            $selected[$internalName] = @{
                Index   = $index
                Version = $versionObject
            }
        }
    }

    return $selected
}

function Get-DownloadUrl {
    param(
        [Parameter(Mandatory)]
        [string]$RepoSlug,

        [Parameter(Mandatory)]
        [string]$TagName
    )

    return "https://github.com/$RepoSlug/releases/download/$TagName/latest.zip"
}

function Update-PluginBlock {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string]$InternalName,

        [Parameter(Mandatory)]
        [string]$CurrentAssemblyVersion,

        [Parameter(Mandatory)]
        [string]$NewAssemblyVersion,

        [Parameter(Mandatory)]
        [string]$DownloadUrl
    )

    $blockPattern = '(?s)\{[^{}]*"InternalName"\s*:\s*"' + [regex]::Escape($InternalName) + '"[^{}]*"AssemblyVersion"\s*:\s*"' + [regex]::Escape($CurrentAssemblyVersion) + '"[^{}]*\}'
    $blockMatch = [regex]::Match($Content, $blockPattern)
    if (-not $blockMatch.Success) {
        throw "未找到需要回写的插件对象: InternalName=$InternalName, AssemblyVersion=$CurrentAssemblyVersion"
    }

    $updatedBlock = $blockMatch.Value
    $assemblyVersionPattern = New-Object System.Text.RegularExpressions.Regex '("AssemblyVersion"\s*:\s*")[^"]+(")'
    $downloadInstallPattern = New-Object System.Text.RegularExpressions.Regex '("DownloadLinkInstall"\s*:\s*")[^"]+(")'
    $downloadUpdatePattern = New-Object System.Text.RegularExpressions.Regex '("DownloadLinkUpdate"\s*:\s*")[^"]+(")'

    $updatedBlock = $assemblyVersionPattern.Replace(
        $updatedBlock,
        [System.Text.RegularExpressions.MatchEvaluator]{
            param($match)
            return $match.Groups[1].Value + $NewAssemblyVersion + $match.Groups[2].Value
        },
        1
    )
    $updatedBlock = $downloadInstallPattern.Replace(
        $updatedBlock,
        [System.Text.RegularExpressions.MatchEvaluator]{
            param($match)
            return $match.Groups[1].Value + $DownloadUrl + $match.Groups[2].Value
        },
        1
    )
    $updatedBlock = $downloadUpdatePattern.Replace(
        $updatedBlock,
        [System.Text.RegularExpressions.MatchEvaluator]{
            param($match)
            return $match.Groups[1].Value + $DownloadUrl + $match.Groups[2].Value
        },
        1
    )

    return $Content.Substring(0, $blockMatch.Index) + $updatedBlock + $Content.Substring($blockMatch.Index + $blockMatch.Length)
}

$pluginMasterContent = Get-Content -Raw -Encoding utf8 $PluginMasterPath
$pluginMaster = $pluginMasterContent | ConvertFrom-Json
$config = Get-Content -Raw -Encoding utf8 $ConfigPath | ConvertFrom-Json
$ruleLookup = Get-RuleLookup -Rules @($config.plugins)
$selectedIndexes = Get-SelectedPluginIndexes -Plugins $pluginMaster

$updatedCount = 0
$selectedItems = $selectedIndexes.GetEnumerator() | Sort-Object Key
$pendingUpdates = @()

foreach ($item in $selectedItems) {
    $pluginIndex = [int]$item.Value.Index
    $plugin = $pluginMaster[$pluginIndex]
    $internalName = [string]$plugin.InternalName

    $rule = $null
    if ($ruleLookup.ContainsKey($internalName)) {
        $rule = $ruleLookup[$internalName]
    }

    $repoSlug = Get-RepoSlugFromUrl -RepoUrl ([string]$plugin.RepoUrl)
    $tagPrefix = $null
    if ($null -ne $rule) {
        if (-not [string]::IsNullOrWhiteSpace([string]$rule.sourceRepo)) {
            $repoSlug = [string]$rule.sourceRepo
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$rule.tagPrefix)) {
            $tagPrefix = [string]$rule.tagPrefix
        }
    }

    $latestRelease = Get-LatestReleaseInfo -RepoSlug $repoSlug -TagPrefix $tagPrefix
    $downloadUrl = Get-DownloadUrl -RepoSlug $repoSlug -TagName $latestRelease.TagName

    $beforeVersion = [string]$plugin.AssemblyVersion
    $beforeInstall = [string]$plugin.DownloadLinkInstall
    $beforeUpdate = [string]$plugin.DownloadLinkUpdate

    $plugin.AssemblyVersion = $latestRelease.AssemblyVersion
    $plugin.DownloadLinkInstall = $downloadUrl
    $plugin.DownloadLinkUpdate = $downloadUrl

    $hasChanged = $false
    if ($beforeVersion -ne [string]$plugin.AssemblyVersion) {
        $hasChanged = $true
    }

    if ($beforeInstall -ne [string]$plugin.DownloadLinkInstall) {
        $hasChanged = $true
    }

    if ($beforeUpdate -ne [string]$plugin.DownloadLinkUpdate) {
        $hasChanged = $true
    }

    if ($hasChanged) {
        $updatedCount++
        $pendingUpdates += [pscustomobject]@{
            InternalName           = $internalName
            CurrentAssemblyVersion = $beforeVersion
            NewAssemblyVersion     = [string]$plugin.AssemblyVersion
            DownloadUrl            = $downloadUrl
        }
        Write-Host "已更新 $internalName -> 版本 $($plugin.AssemblyVersion)，Tag 为 $($latestRelease.TagName)"
    }
    else {
        Write-Host "$internalName 已是最新状态"
    }
}

if ($updatedCount -eq 0) {
    Write-Host "pluginmaster.json 无需更新"
    exit 0
}

$updatedContent = $pluginMasterContent
foreach ($pendingUpdate in $pendingUpdates) {
    $updatedContent = Update-PluginBlock `
        -Content $updatedContent `
        -InternalName $pendingUpdate.InternalName `
        -CurrentAssemblyVersion $pendingUpdate.CurrentAssemblyVersion `
        -NewAssemblyVersion $pendingUpdate.NewAssemblyVersion `
        -DownloadUrl $pendingUpdate.DownloadUrl
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Resolve-Path $PluginMasterPath), $updatedContent, $utf8NoBom)
Write-Host "pluginmaster.json 已写回，共更新 $updatedCount 个插件条目"
