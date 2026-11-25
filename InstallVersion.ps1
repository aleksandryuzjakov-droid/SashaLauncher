param(
    [Parameter(Mandatory=$true)][string]$GameDir,
    [Parameter(Mandatory=$true)][string]$Version
)
# Vanilla installation only, using Mojang's public distribution manifests.
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$root=Join-Path $env:LOCALAPPDATA 'SanieLauncher'
[IO.Directory]::CreateDirectory($root) | Out-Null
$log=Join-Path $root 'installer.log'
Start-Transcript -Path $log -Force | Out-Null
$client=$null;$lock=$null;$success=$false
try {
    if($Version -notmatch '^[^\\/:*?"<>|]+$' -or $Version -eq '.' -or $Version -eq '..'){throw 'Invalid version ID.'}
    $GameDir=[IO.Path]::GetFullPath($GameDir)
    [IO.Directory]::CreateDirectory($GameDir) | Out-Null
    try { $lock=[IO.File]::Open((Join-Path $GameDir '.sanie-install.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
    catch { throw 'Another Sanie installation is active for this game directory.' }
    Add-Type -AssemblyName System.Net.Http
    $client=New-Object Net.Http.HttpClient
    $client.Timeout=[TimeSpan]::FromMinutes(10)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('SanieLauncher/2.3')
    function Official-URL([string]$url) {
        $uri=[Uri]$url
        if($uri.Scheme -ne 'https' -or $uri.Host -notin @('piston-meta.mojang.com','piston-data.mojang.com','launchermeta.mojang.com','launcher.mojang.com','libraries.minecraft.net','resources.download.minecraft.net')) {
            throw "Untrusted download URL: $url"
        }
    }
    function Child([string]$base,[string]$relative){
        $b=[IO.Path]::GetFullPath($base).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
        $p=[IO.Path]::GetFullPath((Join-Path $b $relative))
        if(-not $p.StartsWith($b,[StringComparison]::OrdinalIgnoreCase)){throw "Invalid relative path: $relative"};return $p
    }
    function Fetch-JSON([string]$url){
        Official-URL $url
        $s=$client.GetStringAsync($url).GetAwaiter().GetResult()
        return ($s | ConvertFrom-Json)
    }
    $script:downloaded=0;$script:cached=0
    function Valid([string]$path,[string]$sha1,[long]$size){
        if(-not [IO.File]::Exists($path)){return $false}
        if($size -ge 0 -and (Get-Item -LiteralPath $path).Length -ne $size){return $false}
        return (Get-FileHash -LiteralPath $path -Algorithm SHA1).Hash -eq $sha1
    }
    function Download([string]$url,[string]$path,[string]$sha1,[long]$size=-1){
        Official-URL $url
        if($sha1 -notmatch '^[0-9a-fA-F]{40}$'){throw "Missing/invalid checksum for $path"}
        if(Valid $path $sha1 $size){$script:cached++;return}
        [IO.Directory]::CreateDirectory((Split-Path $path)) | Out-Null
        $tmp=$path+'.sanie-part'
        for($attempt=1;$attempt -le 3;$attempt++){
            $response=$null;$source=$null;$dest=$null
            try {
                $response=$client.GetAsync($url,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
                [void]$response.EnsureSuccessStatusCode()
                Official-URL $response.RequestMessage.RequestUri.AbsoluteUri
                $source=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
                $dest=[IO.File]::Create($tmp)
                $source.CopyTo($dest);$dest.Dispose();$dest=$null
                if(-not (Valid $tmp $sha1 $size)){throw "Checksum or size mismatch: $path"}
                # The old file remains intact until the verified replacement is ready.
                if([IO.File]::Exists($path)){[IO.File]::Replace($tmp,$path,[NullString]::Value)}else{[IO.File]::Move($tmp,$path)}
                $script:downloaded++;return
            } catch {
                if($attempt -eq 3){throw}
                Write-Host "Retry $attempt/3: $($_.Exception.Message)"
                Start-Sleep -Seconds $attempt
            } finally {
                if($dest){$dest.Dispose()};if($source){$source.Dispose()};if($response){$response.Dispose()}
                if([IO.File]::Exists($tmp)){[IO.File]::Delete($tmp)}
            }
        }
    }
    function Prop($o,[string]$name,$default=$null){
        if($null -ne $o -and $null -ne $o.PSObject.Properties[$name]){return $o.$name};return $default
    }
    function Allowed($lib){
        $rules=Prop $lib 'rules';if($null -eq $rules){return $true}
        $allow=$false
        foreach($r in $rules){
            $match=$true;$os=Prop $r 'os'
            if($os){
                if((Prop $os 'name' 'windows') -ne 'windows'){$match=$false}
                $arch=Prop $os 'arch';if($arch -and 'x86_64' -notmatch $arch){$match=$false}
                $ver=Prop $os 'version';if($ver -and [Environment]::OSVersion.Version.ToString() -notmatch $ver){$match=$false}
            }
            $features=Prop $r 'features'
            if($features){foreach($p in $features.PSObject.Properties){if([bool]$p.Value){$match=$false}}}
            if($match){$allow=$r.action -eq 'allow'}
        };return $allow
    }
    Write-Host "Installing vanilla Minecraft $Version to $GameDir"
    Write-Host 'Downloading official version manifest...'
    $manifest=Fetch-JSON 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'
    $entry=$manifest.versions | Where-Object { $_.id -ceq $Version } | Select-Object -First 1
    if(-not $entry){throw "Version not found in Mojang manifest: $Version"}
    $versionRoot=Join-Path $GameDir 'versions'
    $json=Child $versionRoot "$Version/$Version.json"
    # Download verified metadata to a staging file; publish only after completion.
    $staged=$json+'.installing'
    Download $entry.url $staged $entry.sha1
    $meta=Get-Content -LiteralPath $staged -Raw -Encoding UTF8 | ConvertFrom-Json
    if($meta.id -cne $Version){throw 'Version metadata ID mismatch.'}
    Write-Host '[1/4] Downloading client JAR...'
    $jar=Child $versionRoot "$Version/$Version.jar"
    if(-not $meta.downloads.client){throw 'No client download in this version metadata.'}
    Download $meta.downloads.client.url $jar $meta.downloads.client.sha1 $meta.downloads.client.size
    Write-Host '[2/4] Downloading libraries and Windows x64 native archives...'
    $libs=Join-Path $GameDir 'libraries';$n=0
    foreach($lib in @($meta.libraries)){
        if(-not (Allowed $lib)){continue}
        $d=Prop $lib 'downloads';$artifact=Prop $d 'artifact'
        if($artifact){Download $artifact.url (Child $libs $artifact.path) $artifact.sha1 $artifact.size}
        $native=Prop (Prop $lib 'natives') 'windows'
        if($native){
            $classifier=$native.Replace('${arch}','64')
            $a=Prop (Prop $d 'classifiers') $classifier
            if(-not $a){throw "Missing native classifier: $($lib.name) / $classifier"}
            Download $a.url (Child $libs $a.path) $a.sha1 $a.size
        }
        $n++;Write-Progress -Activity 'Libraries' -Status $lib.name -PercentComplete ([Math]::Min(100,$n*100/[Math]::Max(1,$meta.libraries.Count)))
    }
    Write-Progress -Activity 'Libraries' -Completed
    Write-Host '[3/4] Downloading assets (the first install can take several minutes)...'
    $assets=Join-Path $GameDir 'assets';$ai=$meta.assetIndex
    if(-not $ai){throw 'No asset index metadata. This old version is unsupported by this installer.'}
    $indexPath=Child (Join-Path $assets 'indexes') ($ai.id+'.json')
    Download $ai.url $indexPath $ai.sha1 $ai.size
    $index=Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $objects=@($index.objects.PSObject.Properties);$i=0
    foreach($obj in $objects){
        $hash=[string]$obj.Value.hash
        if($hash -notmatch '^[a-f0-9]{40}$'){throw 'Invalid asset hash.'}
        $rel=$hash.Substring(0,2)+'/'+$hash
        Download ('https://resources.download.minecraft.net/'+$rel) (Child (Join-Path $assets 'objects') $rel) $hash $obj.Value.size
        $i++;if($i%20 -eq 0 -or $i -eq $objects.Count){Write-Progress -Activity 'Assets' -Status "$i / $($objects.Count)" -PercentComplete ($i*100/[Math]::Max(1,$objects.Count))}
    }
    Write-Progress -Activity 'Assets' -Completed
    Write-Host '[4/4] Downloading log configuration...'
    $logging=Prop (Prop $meta 'logging') 'client'
    if($logging){$f=$logging.file;Download $f.url (Child (Join-Path $assets 'log_configs') $f.id) $f.sha1 $f.size}
    # Installation is visible as complete only after every dependency is verified.
    if([IO.File]::Exists($json)){[IO.File]::Replace($staged,$json,[NullString]::Value)}else{[IO.File]::Move($staged,$json)}
    $major=Prop (Prop $meta 'javaVersion') 'majorVersion' 8
    $success=$true
    Write-Host "`nINSTALL COMPLETE: $Version" -ForegroundColor Green
    Write-Host "Downloaded: $script:downloaded; verified cache hits: $script:cached"
    Write-Host "Requires 64-bit Java $major. Java is not installed by this script."
    Write-Host 'Return to Sanie Launcher and click Play.'
} catch {
    Write-Host "`nINSTALL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'You can retry: verified files will be reused.'
    Write-Host "Log: $log"
} finally {
    if($client){$client.Dispose()};if($lock){$lock.Dispose()}
    Stop-Transcript | Out-Null
}
Write-Host 'Press Enter to close';[void](Read-Host)
if(-not $success){exit 1}
