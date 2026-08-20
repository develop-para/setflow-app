$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$environmentFile = Join-Path $projectRoot ".env.notion-mcp"

if (-not (Test-Path -LiteralPath $environmentFile -PathType Leaf)) {
    [Console]::Error.WriteLine(
        "Missing .env.notion-mcp. Copy .env.notion-mcp.example and set NOTION_TOKEN."
    )
    exit 1
}

$tokenLine = Get-Content -LiteralPath $environmentFile |
    Where-Object { $_ -match '^\s*NOTION_TOKEN\s*=' } |
    Select-Object -First 1

if ($null -eq $tokenLine) {
    [Console]::Error.WriteLine("NOTION_TOKEN is not defined in .env.notion-mcp.")
    exit 1
}

$notionToken = ($tokenLine -split '=', 2)[1].Trim()
if (
    $notionToken.Length -ge 2 -and
    (($notionToken.StartsWith('"') -and $notionToken.EndsWith('"')) -or
        ($notionToken.StartsWith("'") -and $notionToken.EndsWith("'")))
) {
    $notionToken = $notionToken.Substring(1, $notionToken.Length - 2)
}

if ([string]::IsNullOrWhiteSpace($notionToken) -or $notionToken -like '*replace_with*') {
    [Console]::Error.WriteLine("NOTION_TOKEN in .env.notion-mcp is empty or still a placeholder.")
    exit 1
}

$env:NOTION_TOKEN = $notionToken
try {
    & npx.cmd -y "@notionhq/notion-mcp-server@2.5.1"
    $serverExitCode = $LASTEXITCODE
}
finally {
    Remove-Item Env:NOTION_TOKEN -ErrorAction SilentlyContinue
}

exit $serverExitCode
