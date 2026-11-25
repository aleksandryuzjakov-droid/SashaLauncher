param([ValidateSet('Mods','Server')][string]$Mode='Mods',[string]$GameDir,[string]$Version)
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$headers=@{'User-Agent'='SanieLauncher/2.0 (desktop mod installer)'}
function Api($url) { Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 60 }
function Download($url,$path,$hash,$algorithm='SHA512') {
    if(-not $url.StartsWith('https://')) { throw 'HTTPS required' }
    [IO.Directory]::CreateDirectory((Split-Path $path))|Out-Null
    $temp=$path+'.part'
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $url -Headers $headers -OutFile $temp -TimeoutSec 180
        if($hash -and (Get-FileHash -LiteralPath $temp -Algorithm $algorithm).Hash -ne $hash) { throw 'File checksum mismatch' }
        Move-Item -LiteralPath $temp -Destination $path -Force
    } finally { if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force} }
}
function SafeName($name) {
    if([IO.Path]::GetFileName($name) -ne $name -or $name -match '[\\/:*?"<>|]' -or $name -in @('.','..')){throw 'Unsafe file name'}
    return $name
}
$form=New-Object Windows.Forms.Form
$form.Text='Sanie - '+$Mode
$form.Size=New-Object Drawing.Size(760,700)
$form.StartPosition='CenterScreen'
$form.BackColor=[Drawing.Color]::FromArgb(22,30,32)
$form.ForeColor=[Drawing.Color]::White
$form.Font=New-Object Drawing.Font('Segoe UI',10)
function Label($text,$x,$y,$w=690) {
    $l=New-Object Windows.Forms.Label;$l.Text=$text;$l.SetBounds($x,$y,$w,45);$form.Controls.Add($l);return $l
}
function Button($text,$x,$y,$w=180) {
    $b=New-Object Windows.Forms.Button;$b.Text=$text;$b.SetBounds($x,$y,$w,38);$b.FlatStyle='Flat';$b.BackColor=[Drawing.Color]::FromArgb(40,85,67);$form.Controls.Add($b);return $b
}
$status=Label 'Ready' 20 470
function Status($text){$status.Text=$text;$form.Refresh()}
if($Mode -eq 'Mods') {
    $null=Label "Modrinth / Fabric / Minecraft $Version" 20 15
    $null=Label 'Install compatible mods and required dependencies. Java must be installed separately.' 20 52
    $query=New-Object Windows.Forms.TextBox;$query.SetBounds(20,105,490,30);$form.Controls.Add($query)
    $search=Button 'Search' 530 101
    $list=New-Object Windows.Forms.ListBox;$list.SetBounds(20,150,690,245);$list.DisplayMember='title';$form.Controls.Add($list)
    $install=Button 'Install selected' 20 415 225
    $open=Button 'Open mods folder' 265 415 205
    $script:results=@()
    $search.Add_Click({
        $search.Enabled=$false
        try {
            Status 'Searching Modrinth...'
            $facets='[["project_type:mod"],["categories:fabric"],["versions:'+ $Version +'"]]'
            $r=Api ('https://api.modrinth.com/v2/search?limit=30&query='+[uri]::EscapeDataString($query.Text)+'&facets='+[uri]::EscapeDataString($facets))
            $script:results=@($r.hits);$list.Items.Clear();foreach($hit in $script:results){$null=$list.Items.Add($hit)}
            Status ("Found: "+$script:results.Count)
        } catch { Status $_.Exception.Message } finally {$search.Enabled=$true}
    })
    $open.Add_Click({$p=Join-Path $GameDir 'mods';[IO.Directory]::CreateDirectory($p)|Out-Null;Start-Process explorer.exe -ArgumentList ('"'+$p+'"')})
    function Install-Fabric {
        $base=Join-Path $GameDir "versions\$Version\$Version.json"
        if(-not(Test-Path -LiteralPath $base)) { throw 'Install this Minecraft version from the launcher first.' }
        $loaders=@(Api "https://meta.fabricmc.net/v2/versions/loader/$Version")
        $loader=$loaders|Where-Object {$_.loader.stable}|Select-Object -First 1
        if(-not $loader){throw 'No stable Fabric loader for this Minecraft version'}
        $profile=Api "https://meta.fabricmc.net/v2/versions/loader/$Version/$($loader.loader.version)/profile/json"
        foreach($lib in $profile.libraries) {
            $a=$lib.name.Split(':');if($a.Count -ne 3){throw 'Unsupported library coordinate'}
            $rel=$a[0].Replace('.','/')+'/'+$a[1]+'/'+$a[2]+'/'+$a[1]+'-'+$a[2]+'.jar'
            $dest=Join-Path $GameDir ('libraries/'+$rel)
            if(-not(Test-Path -LiteralPath $dest)){Download ($lib.url.TrimEnd('/')+'/'+$rel) $dest ''}
        }
        $profile|Add-Member -NotePropertyName jar -NotePropertyValue $Version -Force
        $dir=Join-Path $GameDir ('versions/'+$profile.id);[IO.Directory]::CreateDirectory($dir)|Out-Null
        $profile|ConvertTo-Json -Depth 60|Set-Content -LiteralPath (Join-Path $dir ($profile.id+'.json')) -Encoding UTF8
        return $profile.id
    }
    function Install-ModVersion($v,$seen,$depth=0) {
        if($depth -gt 40){throw 'Dependency nesting limit'}
        if($seen.ContainsKey($v.id)){return};$seen[$v.id]=$true
        if($v.game_versions -notcontains $Version -or $v.loaders -notcontains 'fabric'){throw 'Incompatible dependency'}
        foreach($dep in $v.dependencies) {
            if($dep.dependency_type -ne 'required'){continue}
            if($dep.version_id){$dv=Api "https://api.modrinth.com/v2/version/$($dep.version_id)"}
            elseif($dep.project_id){$dv=Find-Version $dep.project_id}
            else{throw 'Unresolved required dependency'}
            Install-ModVersion $dv $seen ($depth+1)
        }
        $file=$v.files|Where-Object {$_.primary}|Select-Object -First 1
        if(-not $file){$file=$v.files|Select-Object -First 1}
        if(-not $file -or -not $file.hashes.sha512){throw 'Missing verified mod file'}
        $name=SafeName $file.filename
        if(-not $name.EndsWith('.jar')){throw 'Expected a JAR mod'}
        $mods=Join-Path $GameDir 'mods';$dest=Join-Path $mods $name
        Status ('Downloading '+$name)
        Download $file.url $dest $file.hashes.sha512
        # Track installed filenames; remove only the previous file for this project.
        $state=Join-Path $GameDir 'sanie-mods';[IO.Directory]::CreateDirectory($state)|Out-Null
        $record=Join-Path $state ((SafeName $v.project_id)+'.txt')
        if(Test-Path -LiteralPath $record){$old=(Get-Content -LiteralPath $record -Raw).Trim();if($old -and $old -ne $name){$old=SafeName $old;Remove-Item -LiteralPath (Join-Path $mods $old) -Force -ErrorAction SilentlyContinue}}
        Set-Content -LiteralPath $record -Value $name -Encoding UTF8
    }
    function Find-Version($id) {
        $url='https://api.modrinth.com/v2/project/'+[uri]::EscapeDataString($id)+'/version?loaders='+[uri]::EscapeDataString('["fabric"]')+'&game_versions='+[uri]::EscapeDataString('["'+$Version+'"]')
        $found=@(Api $url);if(-not $found.Count){throw 'Compatible mod version not found'};return $found[0]
    }
    $install.Add_Click({
        if($list.SelectedIndex -lt 0){return}
        if([Windows.Forms.MessageBox]::Show('Mods are third-party executable code. Install only projects you trust. Continue?','Sanie','YesNo') -ne 'Yes'){return}
        $install.Enabled=$false;$search.Enabled=$false
        try {
            Status 'Installing Fabric loader...';$id=Install-Fabric
            $v=Find-Version $list.SelectedItem.project_id
            Install-ModVersion $v @{}
            Set-Content -LiteralPath (Join-Path $GameDir ("sanie-fabric-$Version.txt")) -Value $id -Encoding ASCII
            Status 'Installed! Enable Fabric in the launcher catalogue before playing.'
        } catch {Status ('Error: '+$_.Exception.Message)} finally {$install.Enabled=$true;$search.Enabled=$true}
    })
} else {
    $title=Label 'Создать свой сервер (BETA)' 20 15
    $sub=Label "Выбери платформу и настрой сервер прямо в Sanie. Minecraft $Version" 20 52
    $recommended=New-Object Windows.Forms.RadioButton;$recommended.Text='★ Рекомендуем! SanieHST — локальный сервер с настройками и плагинами';$recommended.SetBounds(20,105,700,30);$recommended.Checked=$false;$form.Controls.Add($recommended)
    $aternos=New-Object Windows.Forms.RadioButton;$aternos.Text='Aternos — бесплатный внешний хостинг';$aternos.SetBounds(20,140,700,30);$aternos.Checked=$false;$form.Controls.Add($aternos)
    $engine=New-Object Windows.Forms.ComboBox;$engine.DropDownStyle='DropDownList';$engine.Items.AddRange(@('Paper (плагины)','Vanilla (без плагинов)'));$engine.SelectedIndex=0;$engine.SetBounds(20,190,280,30);$form.Controls.Add($engine)
    $ramBox=New-Object Windows.Forms.ComboBox;$ramBox.DropDownStyle='DropDownList';$ramBox.Items.AddRange(@('1 GB RAM','2 GB RAM','4 GB RAM','6 GB RAM','8 GB RAM'));$ramBox.SelectedIndex=1;$ramBox.SetBounds(320,190,150,30);$form.Controls.Add($ramBox)
    $port=New-Object Windows.Forms.TextBox;$port.Text='25565';$port.SetBounds(490,190,100,30);$form.Controls.Add($port)
    $portLabel=Label 'Порт' 595 185 90
    $name=New-Object Windows.Forms.TextBox;$name.Text='Sanie Server';$name.SetBounds(20,240,280,30);$form.Controls.Add($name)
    $motd=New-Object Windows.Forms.TextBox;$motd.Text='Добро пожаловать на SanieHST!';$motd.SetBounds(320,240,365,30);$form.Controls.Add($motd)
    $modeBox=New-Object Windows.Forms.ComboBox;$modeBox.DropDownStyle='DropDownList';$modeBox.Items.AddRange(@('Выживание','Креатив','Приключение','Наблюдение'));$modeBox.SelectedIndex=0;$modeBox.SetBounds(20,290,180,30);$form.Controls.Add($modeBox)
    $difficulty=New-Object Windows.Forms.ComboBox;$difficulty.DropDownStyle='DropDownList';$difficulty.Items.AddRange(@('Мирный','Лёгкий','Нормальный','Сложный'));$difficulty.SelectedIndex=2;$difficulty.SetBounds(220,290,180,30);$form.Controls.Add($difficulty)
    $online=New-Object Windows.Forms.CheckBox;$online.Text='Проверять лицензии (online-mode)';$online.Checked=$true;$online.SetBounds(420,290,280,30);$form.Controls.Add($online)
    $eula=New-Object Windows.Forms.CheckBox;$eula.Text='Я принимаю Minecraft EULA';$eula.SetBounds(20,335,400,30);$form.Controls.Add($eula)
    $create=Button 'Создать SanieHST' 20 390 220
    $plugins=Button 'Настроить плагины' 255 390 220
    $openA=Button 'Открыть Aternos в браузере' 490 390 220
    $pluginList=New-Object Windows.Forms.ListBox;$pluginList.SetBounds(20,435,690,80);$pluginList.Visible=$false;$form.Controls.Add($pluginList)
    $pluginQuery=New-Object Windows.Forms.TextBox;$pluginQuery.SetBounds(20,525,330,30);$pluginQuery.Visible=$false;$form.Controls.Add($pluginQuery)
    $pluginSearch=Button 'Найти плагин' 360 521 150;$pluginSearch.Visible=$false
    $pluginInstall=Button 'Установить выбранный' 520 521 190;$pluginInstall.Visible=$false
    $script:pluginHits=@();$script:serverDir='';$script:serverProcess=$null
    $create.Enabled=$false;$create.Text='Сначала выбери платформу'
    $serverOptions=@($engine,$ramBox,$port,$portLabel,$name,$motd,$modeBox,$difficulty,$online,$eula,$plugins,$pluginList,$pluginQuery,$pluginSearch,$pluginInstall)
    foreach($control in $serverOptions){$control.Visible=$false}
    $chooseHint=Label 'Сначала выбери платформу выше. Файлы сервера и start-server.bat появятся только после подтверждения SanieHST.' 20 300 690
    function Select-Platform {
        if($recommended.Checked){
            foreach($control in $serverOptions){$control.Visible=$true}
            foreach($control in $hstControls){$control.Visible=$true}
            $chooseHint.Text='Настрой SanieHST, прими EULA и нажми «Создать SanieHST». До этого файлы не создаются.'
            $create.Enabled=$true;$create.Text='Создать SanieHST'
        } elseif($aternos.Checked){
            foreach($control in $serverOptions){$control.Visible=$false}
            foreach($control in $hstControls){$control.Visible=$false}
            $chooseHint.Text='Aternos откроется только после нажатия кнопки ниже. Sanie не создаёт файлы Aternos.'
            $create.Enabled=$true;$create.Text='Открыть Aternos'
        }
    }
    $recommended.Add_CheckedChanged({Select-Platform})
    $aternos.Add_CheckedChanged({Select-Platform})
    $serverSelect=New-Object Windows.Forms.ComboBox;$serverSelect.DropDownStyle='DropDownList';$serverSelect.SetBounds(20,565,330,30);$form.Controls.Add($serverSelect)
    $refreshServers=Button 'Обновить серверы' 360 561 150
    $startServer=Button 'Запустить' 520 561 90
    $stopServer=Button 'Остановить' 620 561 90
    $backupServer=Button 'Backup' 20 602 100
    $openServer=Button 'Папка' 130 602 100
    $serverStatus=Label 'SanieHST: сервер не выбран' 245 598 440
    $hstControls=@($serverSelect,$refreshServers,$startServer,$stopServer,$backupServer,$openServer,$serverStatus)
    foreach($control in $hstControls){$control.Visible=$false}
    function Refresh-Servers { $serverSelect.Items.Clear(); $root=Join-Path $GameDir 'SanieHST'; if(Test-Path -LiteralPath $root){Get-ChildItem -LiteralPath $root -Directory|ForEach-Object{[void]$serverSelect.Items.Add($_.FullName)}} }
    function Selected-Server {if($serverSelect.SelectedIndex -lt 0){return $null};return [string]$serverSelect.SelectedItem}
    function Stop-SanieServer {if($script:serverProcess -and -not $script:serverProcess.HasExited){$script:serverProcess.Kill();$script:serverProcess=$null;$serverStatus.Text='SanieHST: сервер остановлен'}}
    $refreshServers.Add_Click({Refresh-Servers})
    $serverSelect.Add_SelectedIndexChanged({$script:serverDir=Selected-Server;$serverStatus.Text=if($script:serverDir){'Выбран: '+$script:serverDir}else{'SanieHST: сервер не выбран'}})
    $startServer.Add_Click({$d=Selected-Server;if(-not $d){Status 'Выбери папку SanieHST.';return};if(-not(Test-Path (Join-Path $d 'start-server.bat'))){Status 'В папке нет start-server.bat.';return};if($script:serverProcess -and -not $script:serverProcess.HasExited){Status 'Сервер уже запущен.';return};$script:serverProcess=Start-Process cmd.exe -ArgumentList '/c','start-server.bat' -WorkingDirectory $d -PassThru;$serverStatus.Text='SanieHST: сервер запускается';Status 'SanieHST запущен.'})
    $stopServer.Add_Click({Stop-SanieServer;Status 'SanieHST остановлен.'})
    $backupServer.Add_Click({$d=Selected-Server;if(-not $d){Status 'Выбери сервер.';return};$dst=Join-Path $d ('backups\world-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.zip');[IO.Directory]::CreateDirectory((Split-Path $dst))|Out-Null;if(Test-Path (Join-Path $d 'world')){Compress-Archive -Path (Join-Path $d 'world') -DestinationPath $dst -Force;Status 'Резервная копия мира создана.'}else{Status 'Папка world ещё не создана.'}})
    $openServer.Add_Click({$d=Selected-Server;if($d){Start-Process explorer.exe -ArgumentList ('"'+$d+'"')}})
    Refresh-Servers
    $openA.Add_Click({Start-Process 'https://aternos.org/'})
    $plugins.Add_Click({$pluginList.Visible=$true;$pluginQuery.Visible=$true;$pluginSearch.Visible=$true;$pluginInstall.Visible=$true;Status 'Плагины ищутся на Hangar (PaperMC). Сначала создай сервер.'})
    $pluginSearch.Add_Click({
        try {
            $pluginSearch.Enabled=$false;$r=Api ('https://hangar.papermc.io/api/v1/projects?limit=20&query='+[uri]::EscapeDataString($pluginQuery.Text)+'&platform=PAPER')
            $script:pluginHits=@($r.result);$pluginList.Items.Clear();foreach($x in $script:pluginHits){$null=$pluginList.Items.Add(($x.name+' — '+$x.description))};Status ('Найдено плагинов: '+$script:pluginHits.Count)
        } catch {Status ('Ошибка поиска: '+$_.Exception.Message)} finally {$pluginSearch.Enabled=$true}
    })
    function Write-ServerConfig($dir) {
        $gamemode=@('survival','creative','adventure','spectator')[$modeBox.SelectedIndex];$diff=@('peaceful','easy','normal','hard')[$difficulty.SelectedIndex]
        $props=@("level-name=$($name.Text)","motd=$($motd.Text)","server-port=$($port.Text)","gamemode=$gamemode","difficulty=$diff","online-mode=$($online.Checked.ToString().ToLower())",'enable-command-block=true','view-distance=10','spawn-protection=0')
        Set-Content -LiteralPath (Join-Path $dir 'server.properties') -Value $props -Encoding ASCII
    }
    $create.Add_Click({
        if($aternos.Checked){Start-Process 'https://aternos.org/';return}
        if(-not $eula.Checked){Status 'Сначала прими EULA.';return}
        if($port.Text -notmatch '^([1-9][0-9]{0,4})$' -or [int]$port.Text -gt 65535){Status 'Порт должен быть от 1 до 65535.';return}
        $pick=New-Object Windows.Forms.FolderBrowserDialog;if($pick.ShowDialog() -ne 'OK'){return};$create.Enabled=$false
        try {
            $dir=$pick.SelectedPath;if(@(Get-ChildItem -LiteralPath $dir -Force).Count){throw 'Выбери пустую папку.'}
            [IO.Directory]::CreateDirectory((Join-Path $dir 'plugins'))|Out-Null;Status 'Скачиваем сервер SanieHST...'
            if($engine.SelectedIndex -eq 0){
                $paper=Api "https://api.papermc.io/v2/projects/paper/versions/$Version";$build=($paper.builds|Select-Object -Last 1)
                $jar=Join-Path $dir 'server.jar';Download "https://api.papermc.io/v2/projects/paper/versions/$Version/builds/$build/downloads/paper-$Version-$build.jar" $jar ''
            } else {
                $manifest=Api 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json';$entry=$manifest.versions|Where-Object {$_.id -eq $Version}|Select-Object -First 1;if(-not $entry){throw 'Версия не найдена'};$meta=Api $entry.url;if(-not $meta.downloads.server){throw 'У версии нет server.jar'};Download $meta.downloads.server.url (Join-Path $dir 'server.jar') $meta.downloads.server.sha1 'SHA1'
            }
            Set-Content -LiteralPath (Join-Path $dir 'eula.txt') -Value 'eula=true' -Encoding ASCII;Write-ServerConfig $dir
            $ramText=($ramBox.SelectedItem -replace ' GB RAM','');Set-Content -LiteralPath (Join-Path $dir 'start-server.bat') -Encoding ASCII -Value "@echo off`r`ncd /d `"%~dp0`"`r`njava -Xms$($ramText)G -Xmx$($ramText)G -jar server.jar nogui`r`npause"
            $script:serverDir=$dir;$serverSelect.Items.Add($dir)|Out-Null;$serverSelect.SelectedItem=$dir;Status 'SanieHST создан! Теперь можно искать и добавлять плагины.';Start-Process explorer.exe -ArgumentList ('"'+$dir+'"')
        } catch {Status ('Ошибка: '+$_.Exception.Message)} finally {$create.Enabled=$true}
    })
    $pluginInstall.Add_Click({
        if(-not $script:serverDir){Status 'Сначала создай SanieHST.';return};if($pluginList.SelectedIndex -lt 0){return}
        try {$x=$script:pluginHits[$pluginList.SelectedIndex];$versions=@(Api ('https://hangar.papermc.io/api/v1/projects/'+$x.namespace+'/'+$x.slug+'/versions?platform=PAPER'));$v=$versions|Select-Object -First 1;$url="https://hangar.papermc.io/api/v1/projects/$($x.namespace)/$($x.slug)/versions/$($v.name)/PAPER/download";$file=Join-Path (Join-Path $script:serverDir 'plugins') ((SafeName ($x.slug+'.jar')));Download $url $file '';Status ('Плагин добавлен: '+$x.name)} catch {Status ('Ошибка плагина: '+$_.Exception.Message)}
    })
}
[void]$form.ShowDialog()
