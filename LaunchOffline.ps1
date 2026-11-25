param(
    [Parameter(Mandatory=$true)][string]$GameDir,
    [Parameter(Mandatory=$true)][string]$Version,
    [Parameter(Mandatory=$true)][string]$Username,
    [int]$Ram=4,
    [string]$JavaPath=''
)
# Offline launch of existing local files only. No network/authentication calls.
$ErrorActionPreference='Stop'
$logDir=Join-Path $env:LOCALAPPDATA 'SanieLauncher'
[IO.Directory]::CreateDirectory($logDir) | Out-Null
$launcherLog=Join-Path $logDir 'launcher.log'
Start-Transcript -Path $launcherLog -Force | Out-Null
try {
    if ($Username -notmatch '^[A-Za-z0-9_]{3,16}$') { throw 'Username must contain 3-16 ASCII letters, digits or underscores.' }
    $Ram=[Math]::Max(2,[Math]::Min(16,$Ram))
    $GameDir=[IO.Path]::GetFullPath($GameDir)
    function Get-Property($obj,[string]$key,$default=$null) {
        if ($null -ne $obj -and $null -ne $obj.PSObject.Properties[$key]) { return $obj.$key }
        return $default
    }
    function Require-File([string]$path) {
        if (-not [IO.File]::Exists($path)) { throw "Missing local file: $path. Install this version completely with a trusted launcher first." }
        return $path
    }
    function Safe-Child([string]$root,[string]$relative) {
        $base=[IO.Path]::GetFullPath($root).TrimEnd('\')+'\'
        $p=[IO.Path]::GetFullPath((Join-Path $base $relative))
        if (-not $p.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)) { throw "Path outside expected directory: $relative" }
        return $p
    }
    $seen=@{}
    function Read-Version([string]$id) {
        if ($id -notmatch '^[^\\/:*?"<>|]+$' -or $id -eq '.' -or $id -eq '..') { throw 'Invalid version ID.' }
        if ($seen.ContainsKey($id)) { throw 'Cyclic version inheritance.' }; $seen[$id]=$true
        $path=Safe-Child (Join-Path $GameDir 'versions') "$id\$id.json"
        $v=Get-Content -LiteralPath (Require-File $path) -Raw -Encoding UTF8 | ConvertFrom-Json
        $parent=Get-Property $v 'inheritsFrom'
        if ($parent) {
            $b=Read-Version $parent
            $vlibs=@(Get-Property $v 'libraries' @()); $blibs=@(Get-Property $b 'libraries' @())
            foreach ($prop in $b.PSObject.Properties) {
                if ($null -eq $v.PSObject.Properties[$prop.Name]) { $v | Add-Member NoteProperty $prop.Name $prop.Value }
            }
            $v.libraries=@($blibs)+@($vlibs)
            # Inherited modern arguments are appended in parent -> child order.
            if ($v.arguments -and $b.arguments) {
                foreach($kind in @('jvm','game')) {
                    $own=Get-Property $v.arguments $kind @()
                    $baseArgs=Get-Property $b.arguments $kind @()
                    if (-not [object]::ReferenceEquals($v.arguments,$b.arguments)) {
                        $v.arguments | Add-Member NoteProperty $kind (@($baseArgs)+@($own)) -Force
                    }
                }
            }
            if (-not (Get-Property $v 'jar')) { $v | Add-Member NoteProperty 'jar' (Get-Property $b 'jar' $parent) -Force }
        }
        return $v
    }
    $meta=Read-Version $Version
    $major=[int](Get-Property (Get-Property $meta 'javaVersion') 'majorVersion' 8)
    $component=Get-Property (Get-Property $meta 'javaVersion') 'component' ''
    function Java-Major([string]$path) {
        $release=Join-Path (Split-Path (Split-Path $path)) 'release'
        if (Test-Path -LiteralPath $release) {
            $s=Get-Content -LiteralPath $release -Raw
            if($s -match 'JAVA_VERSION="(?:1\.)?(\d+)') { return [int]$Matches[1] }
        }
        return 0
    }
    if (-not $JavaPath) {
        $candidates=@()
        if ($component) {
            $rt=Join-Path $GameDir "runtime\$component"
            if (Test-Path -LiteralPath $rt) { $candidates+=@(Get-ChildItem -LiteralPath $rt -Filter java.exe -Recurse -ErrorAction SilentlyContinue | ForEach-Object FullName) }
        }
        if($env:JAVA_HOME) { $candidates+=(Join-Path $env:JAVA_HOME 'bin\java.exe') }
        foreach($root in @((Join-Path $env:ProgramFiles 'Java'),(Join-Path $env:ProgramFiles 'Eclipse Adoptium'),(Join-Path $env:ProgramFiles 'Microsoft'))) {
            if(Test-Path -LiteralPath $root) { $candidates+=@(Get-ChildItem -LiteralPath $root -Filter java.exe -Recurse -ErrorAction SilentlyContinue | ForEach-Object FullName) }
        }
        $cmd=Get-Command java.exe -ErrorAction SilentlyContinue
        if($cmd) { $candidates+=$cmd.Source }
        $JavaPath=$candidates | Where-Object { (Test-Path -LiteralPath $_) -and (Java-Major $_) -eq $major } | Select-Object -First 1
        if(-not $JavaPath) { throw "Java $major not found. Install a 64-bit Java $major JDK, or set [Launch] JavaPath in profile.ini." }
    }
    $JavaPath=Require-File $JavaPath
    $javaHome=Split-Path (Split-Path $JavaPath)
    $javaRelease=Join-Path $javaHome 'release'
    $arch='x86_64'
    if(Test-Path -LiteralPath $javaRelease) {
        $releaseText=Get-Content -LiteralPath $javaRelease -Raw
        if($releaseText -match 'OS_ARCH="(x86|i386|i686)"') { throw '32-bit Java is unsupported. Install 64-bit Java.' }
        if($releaseText -match 'OS_ARCH="(aarch64|arm64)"') { $arch='aarch64' }
    }
    function Allowed($entry) {
        $rules=Get-Property $entry 'rules'
        if ($null -eq $rules) { return $true }
        $allow=$false
        foreach($rule in $rules) {
            $match=$true; $os=Get-Property $rule 'os'
            if($os) {
                if ((Get-Property $os 'name' 'windows') -ne 'windows') { $match=$false }
                $ar=Get-Property $os 'arch'; if($ar -and $arch -notmatch $ar) { $match=$false }
                $ver=Get-Property $os 'version'; if($ver -and [Environment]::OSVersion.Version.ToString() -notmatch $ver) { $match=$false }
            }
            $features=Get-Property $rule 'features'
            if($features) { foreach($p in $features.PSObject.Properties) { if([bool]$p.Value) { $match=$false } } }
            if($match) { $allow=$rule.action -eq 'allow' }
        }
        return $allow
    }
    $nativeDir=Join-Path $logDir ('natives\'+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($nativeDir) | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    function Extract-Natives([string]$jar,$excludes) {
        $zip=[IO.Compression.ZipFile]::OpenRead($jar)
        try { foreach($entry in $zip.Entries) {
            $skip=$entry.FullName.StartsWith('META-INF/');foreach($e in @($excludes)) { if($e -and $entry.FullName.StartsWith($e)) { $skip=$true } }
            if($skip -or -not $entry.Name) { continue }
            $out=Safe-Child $nativeDir $entry.FullName
            [IO.Directory]::CreateDirectory((Split-Path $out)) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$out,$true)
        } } finally { $zip.Dispose() }
    }
    $cp=New-Object 'System.Collections.Generic.List[string]'
    $libs=Join-Path $GameDir 'libraries'
    # Keep child library revisions instead of duplicate parent artifacts.
    $libraryMap=[ordered]@{}
    foreach($lib in @($meta.libraries)) {
        if(-not (Allowed $lib)) { continue }
        $parts=$lib.name -split ':'
        $key=($parts | Select-Object -First 2) -join ':'
        if($parts.Count -gt 3) { $key+=':'+$parts[3] }
        $libraryMap[$key]=$lib
    }
    foreach($lib in $libraryMap.Values) {
        if(-not (Allowed $lib)) { continue }
        $downloads=Get-Property $lib 'downloads'
        $artifact=Get-Property $downloads 'artifact'
        $native=Get-Property (Get-Property $lib 'natives') 'windows'
        if($artifact) { $cp.Add((Require-File (Safe-Child $libs $artifact.path))) }
        elseif(-not $native) {
            $p=$lib.name -split ':';if($p.Count -lt 3) { throw 'Invalid Maven coordinate.' }
            $suffix='';if($p.Count -gt 3) { $suffix='-'+$p[3] }
            $relative=($p[0].Replace('.','/'))+'/'+$p[1]+'/'+$p[2]+'/'+$p[1]+'-'+$p[2]+$suffix+'.jar'
            $cp.Add((Require-File (Safe-Child $libs $relative)))
        }
        if($native) {
            $classifier=$native.Replace('${arch}','64')
            $n=Get-Property (Get-Property $downloads 'classifiers') $classifier
            if(-not $n) { throw "Missing native classifier metadata: $classifier" }
            Extract-Natives (Require-File (Safe-Child $libs $n.path)) (Get-Property (Get-Property $lib 'extract') 'exclude' @())
        }
    }
    $jarId=Get-Property $meta 'jar' $Version
    $cp.Add((Require-File (Safe-Child (Join-Path $GameDir 'versions') "$jarId\$jarId.jar")))
    $assets=Join-Path $GameDir 'assets'
    $assetId=Get-Property (Get-Property $meta 'assetIndex') 'id' (Get-Property $meta 'assets' 'legacy')
    $indexFile=Require-File (Safe-Child (Join-Path $assets 'indexes') "$assetId.json")
    $index=Get-Content -LiteralPath $indexFile -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach($o in $index.objects.PSObject.Properties) {
        $hash=[string]$o.Value.hash
        if($hash -notmatch '^[a-f0-9]{40}$') { throw 'Invalid asset hash.' }
        $source=Require-File (Join-Path $assets ('objects\'+$hash.Substring(0,2)+'\'+$hash))
        foreach($destRoot in @($(if(Get-Property $index 'virtual' $false) { Join-Path $assets "virtual\$assetId" }),$(if(Get-Property $index 'map_to_resources' $false) { Join-Path $GameDir 'resources' }))) {
            if($destRoot) { $dest=Safe-Child $destRoot $o.Name;[IO.Directory]::CreateDirectory((Split-Path $dest)) | Out-Null;if(-not (Test-Path -LiteralPath $dest)) { Copy-Item -LiteralPath $source -Destination $dest } }
        }
    }
    $md5=[Security.Cryptography.MD5]::Create()
    try { $bytes=$md5.ComputeHash([Text.Encoding]::UTF8.GetBytes('OfflinePlayer:'+$Username)) } finally { $md5.Dispose() }
    $bytes[6]=($bytes[6] -band 15) -bor 48;$bytes[8]=($bytes[8] -band 63) -bor 128
    $uuid=($bytes | ForEach-Object { $_.ToString('x2') }) -join ''
    $values=@{
        auth_player_name=$Username;version_name=$Version;game_directory=$GameDir;assets_root=$assets
        assets_index_name=$assetId;auth_uuid=$uuid;auth_access_token='0';user_type='legacy';version_type='release'
        user_properties='{}';auth_session='0';natives_directory=$nativeDir;launcher_name='Sanie';launcher_version='2.1'
        classpath=($cp -join ';');classpath_separator=';';library_directory=$libs
        game_assets=(Join-Path $assets "virtual\$assetId");resolution_width='1280';resolution_height='720'
        clientid='';auth_xuid=''
    }
    function Expand-Arg([string]$s) {
        foreach($key in $values.Keys) { $s=$s.Replace('${'+$key+'}',[string]$values[$key]) }
        if($s -match '\$\{[^}]+\}') { throw "Unsupported argument placeholder: $s" };return $s
    }
    function Collect-Args($entries) {
        foreach($e in @($entries)) {
            if($null -eq $e) { continue }
            if ($e -is [string]) { Expand-Arg $e }
            elseif(Allowed $e) { foreach($s in @($e.value)) { if($null -ne $s) { Expand-Arg $s } } }
        }
    }
    $jvm=@("-Xmx${Ram}G",'-XX:+UseG1GC')
    if(Get-Property $meta 'arguments') {
        $jvm+=@(Collect-Args $meta.arguments.jvm);$game=@(Collect-Args $meta.arguments.game)
    } else {
        $jvm+=@(('-Djava.library.path='+$nativeDir),'-cp',($cp -join ';'))
        $game=@(Collect-Args ([regex]::Matches([string]$meta.minecraftArguments,'"([^"]*)"|(\S+)') | ForEach-Object { if($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value } }))
    }
    $logging=Get-Property (Get-Property $meta 'logging') 'client'
    if($logging) {
        $logFile=Require-File (Safe-Child (Join-Path $assets 'log_configs') $logging.file.id)
        $jvm+=([string]$logging.argument).Replace('${path}',$logFile)
    }
    # Empty JVM tokens before mainClass are interpreted by Java as an empty
    # main-class name. Never remove empty GAME arguments (e.g. clientId/xuid).
    $cleanJvm=New-Object 'System.Collections.Generic.List[string]'
    foreach($arg in @($jvm)) {
        if($null -eq $arg -or [string]::IsNullOrWhiteSpace([string]$arg)) {
            Write-Host 'Skipped an empty JVM argument.'
            continue
        }
        $cleanJvm.Add([string]$arg)
    }
    $jvm=@($cleanJvm.ToArray())
    $main=[string](Get-Property $meta 'mainClass')
    $main=$main.Trim()
    if($main -notmatch '^[A-Za-z_$][A-Za-z0-9_$]*(\.[A-Za-z_$][A-Za-z0-9_$]*)+$') {
        throw "Invalid mainClass in version JSON: <$main>"
    }
    for($i=0;$i -lt $jvm.Count;$i++) {
        if($jvm[$i] -in @('-cp','-classpath','--class-path')) {
            if($i+1 -ge $jvm.Count -or [string]::IsNullOrWhiteSpace($jvm[$i+1])) {
                throw 'JVM classpath option has no value.'
            }
            $i++
            continue
        }
        if(-not $jvm[$i].StartsWith('-')) {
            throw "Unexpected JVM token before mainClass at index ${i}: <$($jvm[$i])>"
        }
    }
    # Do not trust a possibly malformed/inherited classpath in metadata.
    # Build exactly one classpath option from the files verified above.
    $canonicalCP=([string[]]$cp.ToArray()) -join ';'
    if([string]::IsNullOrWhiteSpace($canonicalCP)) { throw 'Computed classpath is empty.' }
    $normalizedJvm=New-Object 'System.Collections.Generic.List[string]'
    for($i=0;$i -lt $jvm.Count;$i++) {
        $arg=[string]$jvm[$i]
        if($arg -in @('-cp','-classpath','--class-path')) { $i++; continue }
        if($arg.StartsWith('--class-path=' ) -or $arg.StartsWith('-Djava.class.path=')) { continue }
        if(-not [string]::IsNullOrWhiteSpace($arg)) { $normalizedJvm.Add($arg) }
    }
    $normalizedJvm.Add('-cp');$normalizedJvm.Add($canonicalCP)
    $jvm=@($normalizedJvm.ToArray())
    $mainEntry=$main.Replace('.','/')+'.class'
    $mainJar=$null
    foreach($jar in $cp) {
        try {
            $archive=[IO.Compression.ZipFile]::OpenRead($jar)
            try { if($null -ne $archive.GetEntry($mainEntry)) { $mainJar=$jar } }
            finally { $archive.Dispose() }
        } catch { throw "Invalid or unreadable classpath JAR: $jar. $($_.Exception.Message)" }
        if($mainJar) { break }
    }
    if(-not $mainJar) {
        throw "Class $mainEntry is absent from all $($cp.Count) classpath JARs. Check the client JAR: $(Join-Path $GameDir "versions\$jarId\$jarId.jar"). Reinstall this version with your trusted launcher; do not rename server JARs as client JARs."
    }
    Write-Host "Main class found in: $mainJar"
    Write-Host "Classpath entries: $($cp.Count)"
    [IO.File]::WriteAllLines((Join-Path $logDir 'classpath.txt'),[string[]]$cp.ToArray(),[Text.Encoding]::UTF8)
    function Quote-Arg([string]$a) {
        # Windows CRT command-line escaping, including backslashes before quotes.
        return '"'+([regex]::Replace(([regex]::Replace($a,'(\\*)"','$1$1\"')),'(\\+)$','$1$1'))+'"'
    }
    # Own the offline identity and mandatory vanilla launch options explicitly.
    # Preserve unrelated metadata options (including mod-loader parameters).
    $offlineOptions=[ordered]@{
        '--username'=[string]$Username
        '--version'=[string]$Version
        '--gameDir'=[string]$GameDir
        '--assetsDir'=[string]$assets
        '--assetIndex'=[string]$assetId
        '--uuid'=[string]$uuid
        '--accessToken'='0'
        '--userType'='legacy'
        '--versionType'=[string](Get-Property $meta 'type' 'release')
    }
    $gameArgs=New-Object 'System.Collections.Generic.List[string]'
    for($i=0;$i -lt @($game).Count;$i++) {
        $token=[string]$game[$i]
        $option=($token -split '=',2)[0]
        if($offlineOptions.Contains($option)) {
            if($token.IndexOf('=') -lt 0 -and $i+1 -lt @($game).Count -and -not ([string]$game[$i+1]).StartsWith('--')) { $i++ }
            continue
        }
        if($null -ne $game[$i]) { $gameArgs.Add($token) }
    }
    foreach($option in $offlineOptions.Keys) {
        $value=[string]$offlineOptions[$option]
        if([string]::IsNullOrWhiteSpace($value)) { throw "Empty required game option: $option" }
        $gameArgs.Add([string]$option);$gameArgs.Add($value)
    }
    $game=@($gameArgs.ToArray())
    Write-Host "Game arguments: $($game.Count) tokens; offline version=$Version; accessToken=0"
    $all=@($jvm)+@($main)+@($game)
    $command=($all | ForEach-Object { Quote-Arg ([string]$_) }) -join ' '
    if($command.Length -gt 30000) { throw 'Command line too long. Use a shorter game-directory path.' }
    Write-Host "Starting $Version as offline player $Username using $JavaPath"
    Write-Host "Main class: <$main>"
    $debugLines=New-Object 'System.Collections.Generic.List[string]'
    $debugLines.Add("Java: $JavaPath")
    $debugLines.Add("Main class: <$main>")
    for($i=0;$i -lt $all.Count;$i++) {
        $section=if($i -lt $jvm.Count){'JVM'}elseif($i -eq $jvm.Count){'MAIN'}else{'GAME'}
        $debugLines.Add(('{0}[{1}] = <{2}>' -f $section,$i,[string]$all[$i]))
    }
    [IO.File]::WriteAllLines((Join-Path $logDir 'launch-arguments.txt'),$debugLines.ToArray(),[Text.Encoding]::UTF8)
    # Java 9+ can read an argument file directly. This avoids the extra Windows
    # command-line quoting layer and preserves intentional empty GAME values.
    if($major -ge 9) {
        $argFile=Join-Path $nativeDir 'java-arguments.txt'
        $argLines=@($all | ForEach-Object {
            '"'+([string]$_).Replace('\','\\').Replace('"','\"').Replace("`r",'\r').Replace("`n",'\n').Replace("`t",'\t')+'"'
        })
        [IO.File]::WriteAllLines($argFile,[string[]]$argLines,(New-Object Text.UTF8Encoding($false)))
        $command=Quote-Arg ('@'+$argFile)
    }
    $pi=New-Object Diagnostics.ProcessStartInfo
    $pi.FileName=$JavaPath;$pi.Arguments=$command;$pi.WorkingDirectory=$GameDir
    $pi.UseShellExecute=$false
    $process=[Diagnostics.Process]::Start($pi)
    $process.WaitForExit()
    if($process.ExitCode -ne 0) { throw "Minecraft exited with code $($process.ExitCode). See .minecraft\logs\latest.log and launcher.log." }
} catch {
    Write-Host "`nLAUNCH ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Launcher log: $launcherLog"
    Write-Host 'Press Enter to close';[void](Read-Host)
} finally {
    if($nativeDir -and (Test-Path -LiteralPath $nativeDir)) { Remove-Item -LiteralPath $nativeDir -Recurse -Force -ErrorAction SilentlyContinue }
    Stop-Transcript | Out-Null
}
