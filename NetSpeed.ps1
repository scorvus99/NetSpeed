if ((Get-ExecutionPolicy -Scope CurrentUser) -eq "Restricted") {
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Пути к файлам настроек и трафика ---
$script:appPath = if ($env:PS2EXE_PATH) {
    $env:PS2EXE_PATH
} elseif ($PSCommandPath) {
    $PSCommandPath
} else {
    [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
}
$script:appDir = Split-Path $script:appPath -Parent
if (-not $script:appDir) { $script:appDir = [Environment]::CurrentDirectory }

$script:settingsPath     = Join-Path $script:appDir "netspeed_settings.json"
$script:trafficPath      = Join-Path $script:appDir "netspeed_traffic.json"
$script:trafficTablePath = Join-Path $script:appDir "netspeed_traffic.txt"

# --- Переменные трафика ---
$script:trafficHistory     = @{}
$script:currentDateKey     = [DateTime]::Today.ToString("yyyy-MM-dd")
$script:trafficSaveCounter = 0

# --- Настройки по умолчанию ---
$script:defaultSettings = @{
    opacity          = 1.0
    hoverOpacity     = 1.0
    isPinned         = $false
    alwaysOnTop      = $true
    clickThrough     = $false
    useBits          = $false
    updateInterval   = 1000
    lineThickness    = 1
    pixelsPerPoint   = 10
    bgColor          = "#1E1E1E"
    graphBg          = "#181818"
    gridColor        = "#373737"
    scaleTextColor   = "#AAAAAA"
    downloadColor    = "#0080FF"
    uploadColor      = "#BBDDFF"
    totalColor       = "#B3D9FF"
    showGraphTotal   = $false
    showGraphDown    = $true
    showGraphUp      = $true
    showLabelTotal   = $false
    showLabelDown    = $true
    showLabelUp      = $true
    showTrafficTotal = $true
    showTrafficDown  = $false
    showTrafficUp    = $false
    labelPosition    = 0  # 0=сверху, 1=снизу, 2=слева, 3=справа
    fontSize         = 10
    scaleFontSize    = 8
    windowWidth      = 328
    windowHeight     = 200
    windowX          = -1
    windowY          = -1
    selectedInterface = ""  # Пустая строка = все интерфейсы
}

# --- Функция загрузки настроек ---
function LoadSettings {
    if (Test-Path $script:settingsPath) {
        try {
            $json = Get-Content $script:settingsPath -Raw
            return $json | ConvertFrom-Json
        } catch {
            return $null
        }
    }
    return $null
}

# --- Функция сохранения настроек ---
function SaveSettings {
    $settings = @{
        opacity         = $script:opacity
        hoverOpacity    = $script:hoverOpacity
        isPinned        = $script:isPinned
        alwaysOnTop     = $script:alwaysOnTop
        clickThrough    = $script:clickThrough
        useBits         = $script:useBits
        updateInterval  = $script:updateInterval
        lineThickness   = $script:lineThickness
        pixelsPerPoint  = $script:pixelsPerPoint
        bgColor         = "#" + $script:bgColor.R.ToString("X2") + $script:bgColor.G.ToString("X2") + $script:bgColor.B.ToString("X2")
        graphBg         = "#" + $script:graphBg.R.ToString("X2") + $script:graphBg.G.ToString("X2") + $script:graphBg.B.ToString("X2")
        gridColor       = "#" + $script:gridColor.R.ToString("X2") + $script:gridColor.G.ToString("X2") + $script:gridColor.B.ToString("X2")
        scaleTextColor  = "#" + $script:scaleTextColor.R.ToString("X2") + $script:scaleTextColor.G.ToString("X2") + $script:scaleTextColor.B.ToString("X2")
        downloadColor   = "#" + $script:downloadColor.R.ToString("X2") + $script:downloadColor.G.ToString("X2") + $script:downloadColor.B.ToString("X2")
        uploadColor     = "#" + $script:uploadColor.R.ToString("X2") + $script:uploadColor.G.ToString("X2") + $script:uploadColor.B.ToString("X2")
        totalColor      = "#" + $script:totalColor.R.ToString("X2") + $script:totalColor.G.ToString("X2") + $script:totalColor.B.ToString("X2")
        showGraphTotal  = $script:showGraphTotal
        showGraphDown   = $script:showGraphDown
        showGraphUp     = $script:showGraphUp
        showLabelTotal  = $script:showLabelTotal
        showLabelDown   = $script:showLabelDown
        showLabelUp     = $script:showLabelUp
        showTrafficTotal = $script:showTrafficTotal
        showTrafficDown = $script:showTrafficDown
        showTrafficUp   = $script:showTrafficUp
        labelPosition   = $script:labelPosition
        fontSize        = $script:fontSize
        scaleFontSize   = $script:scaleFontSize
        windowWidth     = $form.Width
        windowHeight    = $form.Height
        windowX         = $form.Location.X
        windowY         = $form.Location.Y
        selectedInterface = $script:selectedInterface
    }

    $json = $settings | ConvertTo-Json -Depth 10
    Set-Content $script:settingsPath -Value $json
    SaveTrafficHistory
}

# --- Функции сохранения и получения истории трафика ---
function LoadTrafficHistory {
    $script:trafficHistory = @{}
    $todayKey = [DateTime]::Today.ToString("yyyy-MM-dd")
    $script:currentDateKey = $todayKey

    if (Test-Path $script:trafficPath) {
        try {
            $rawJson = Get-Content $script:trafficPath -Raw
            if ($rawJson) {
                $json = $rawJson | ConvertFrom-Json
                if ($json -and $json.psobject.Properties['history']) {
                    foreach ($prop in $json.history.psobject.Properties) {
                        $key = $prop.Name
                        $val = $prop.Value
                        $down = if ($val.Down) { [long]$val.Down } else { 0L }
                        $up   = if ($val.Up)   { [long]$val.Up }   else { 0L }
                        $script:trafficHistory[$key] = @{ Down = $down; Up = $up }
                    }
                }
            }
        } catch {}
    }

    if ($script:trafficHistory.ContainsKey($todayKey)) {
        $script:totalTrafficDown = [long]$script:trafficHistory[$todayKey].Down
        $script:totalTrafficUp   = [long]$script:trafficHistory[$todayKey].Up
    } else {
        $script:totalTrafficDown = 0L
        $script:totalTrafficUp   = 0L
        $script:trafficHistory[$todayKey] = @{ Down = 0L; Up = 0L }
    }
    $script:totalTrafficBoth = $script:totalTrafficDown + $script:totalTrafficUp
}

function SaveTrafficHistory {
    try {
        $todayKey = $script:currentDateKey
        if (-not $todayKey) {
            $todayKey = [DateTime]::Today.ToString("yyyy-MM-dd")
            $script:currentDateKey = $todayKey
        }

        $script:trafficHistory[$todayKey] = @{
            Down = [long]$script:totalTrafficDown
            Up   = [long]$script:totalTrafficUp
        }

        $dataToSave = @{
            history = $script:trafficHistory
        }
        $json = $dataToSave | ConvertTo-Json -Depth 10
        Set-Content -Path $script:trafficPath -Value $json -Encoding UTF8

        SaveTrafficTableFile
    } catch {}
}

function GetTrafficTableRows {
    $rows = New-Object System.Collections.ArrayList
    $today = [DateTime]::Today

    if ($script:currentDateKey) {
        $script:trafficHistory[$script:currentDateKey] = @{
            Down = [long]$script:totalTrafficDown
            Up   = [long]$script:totalTrafficUp
        }
    }

    $down30 = 0L; $up30 = 0L
    $down7  = 0L; $up7  = 0L
    $downToday = 0L; $upToday = 0L
    $dateEntries = @()

    foreach ($key in $script:trafficHistory.Keys) {
        try {
            $parsedDate = [DateTime]::ParseExact($key, "yyyy-MM-dd", $null)
            $d = [long]$script:trafficHistory[$key].Down
            $u = [long]$script:trafficHistory[$key].Up
            $diffDays = ($today - $parsedDate.Date).Days

            if ($diffDays -ge 0 -and $diffDays -lt 30) { $down30 += $d; $up30 += $u }
            if ($diffDays -ge 0 -and $diffDays -lt 7)  { $down7  += $d; $up7  += $u }
            if ($diffDays -eq 0)                       { $downToday += $d; $upToday += $u }

            if ($diffDays -gt 0) {
                $dateEntries += [PSCustomObject]@{
                    Date    = $parsedDate
                    DateStr = $parsedDate.ToString("dd.MM.yyyy")
                    Down    = $d
                    Up      = $u
                    Total   = $d + $u
                }
            }
        } catch {}
    }

    [void]$rows.Add([PSCustomObject]@{ Дата = "За 30 дней"; Загрузка = FormatTraffic $down30; Отдача = FormatTraffic $up30; Общее = FormatTraffic ($down30 + $up30) })
    [void]$rows.Add([PSCustomObject]@{ Дата = "За 7 дней";  Загрузка = FormatTraffic $down7;  Отдача = FormatTraffic $up7;  Общее = FormatTraffic ($down7 + $up7) })
    [void]$rows.Add([PSCustomObject]@{ Дата = "Сегодня";    Загрузка = FormatTraffic $downToday; Отдача = FormatTraffic $upToday; Общее = FormatTraffic ($downToday + $upToday) })

    $sortedEntries = $dateEntries | Sort-Object Date -Descending
    foreach ($entry in $sortedEntries) {
        [void]$rows.Add([PSCustomObject]@{ Дата = $entry.DateStr; Загрузка = FormatTraffic $entry.Down; Отдача = FormatTraffic $entry.Up; Общее = FormatTraffic $entry.Total })
    }
    return $rows
}

function SaveTrafficTableFile {
    try {
        $rows = GetTrafficTableRows
        $header = "{0,-15} {1,-15} {2,-15} {3,-15}" -f "Дата", "Загрузка", "Отдача", "Общее"
        $lines = New-Object System.Collections.ArrayList
        [void]$lines.Add($header)

        foreach ($r in $rows) {
            $line = "{0,-15} {1,-15} {2,-15} {3,-15}" -f $r.Дата, $r.Загрузка, $r.Отдача, $r.Общее
            [void]$lines.Add($line)
        }

        $text = $lines -join "`r`n"
        Set-Content -Path $script:trafficTablePath -Value $text -Encoding UTF8
    } catch {}
}

function ShowTrafficWindow {
    $trafficForm = New-Object System.Windows.Forms.Form
    $trafficForm.Text = "Статистика трафика - NetSpeed"
    $trafficForm.Size = New-Object System.Drawing.Size(600, 450)
    $trafficForm.StartPosition = "CenterParent"
    $trafficForm.BackColor = $script:bgColor
    $trafficForm.ForeColor = [System.Drawing.Color]::White
    $trafficForm.FormBorderStyle = "FixedDialog"
    $trafficForm.MaximizeBox = $false
    $trafficForm.MinimizeBox = $false

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = [System.Windows.Forms.DockStyle]::Fill
    $grid.BackgroundColor = $script:graphBg
    $grid.ForeColor = [System.Drawing.Color]::White
    $grid.DefaultCellStyle.BackColor = $script:graphBg
    $grid.DefaultCellStyle.ForeColor = [System.Drawing.Color]::White
    $grid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
    $grid.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
    $grid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(37, 37, 38)
    $grid.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
    $grid.EnableHeadersVisualStyles = $false
    $grid.GridColor = $script:gridColor
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.AllowUserToResizeRows = $false
    $grid.RowHeadersVisible = $false
    $grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $grid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect

    [void]$grid.Columns.Add("Date", "Дата")
    [void]$grid.Columns.Add("Down", "Загрузка")
    [void]$grid.Columns.Add("Up", "Отдача")
    [void]$grid.Columns.Add("Total", "Общее")

    function PopulateGrid {
        $grid.Rows.Clear()
        $rows = GetTrafficTableRows
        foreach ($r in $rows) {
            [void]$grid.Rows.Add($r.Дата, $r.Загрузка, $r.Отдача, $r.Общее)
        }
    }

    PopulateGrid

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $panel.Height = 45
    $panel.BackColor = $script:bgColor

    $btnRefresh = New-Object System.Windows.Forms.Button
    $btnRefresh.Text = "Обновить"
    $btnRefresh.Size = New-Object System.Drawing.Size(90, 28)
    $btnRefresh.Location = New-Object System.Drawing.Point(12, 8)
    $btnRefresh.FlatStyle = "Flat"
    $btnRefresh.ForeColor = [System.Drawing.Color]::White
    $btnRefresh.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)
    $btnRefresh.Add_Click({ PopulateGrid })

    $btnOpenFile = New-Object System.Windows.Forms.Button
    $btnOpenFile.Text = "Открыть файл таблицы"
    $btnOpenFile.Size = New-Object System.Drawing.Size(160, 28)
    $btnOpenFile.Location = New-Object System.Drawing.Point(110, 8)
    $btnOpenFile.FlatStyle = "Flat"
    $btnOpenFile.ForeColor = [System.Drawing.Color]::White
    $btnOpenFile.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)
    $btnOpenFile.Add_Click({
        SaveTrafficHistory
        if (Test-Path $script:trafficTablePath) {
            [System.Diagnostics.Process]::Start("notepad.exe", $script:trafficTablePath)
        }
    })

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Закрыть"
    $btnClose.Size = New-Object System.Drawing.Size(90, 28)
    $btnClose.Location = New-Object System.Drawing.Point(480, 8)
    $btnClose.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $btnClose.FlatStyle = "Flat"
    $btnClose.ForeColor = [System.Drawing.Color]::White
    $btnClose.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)
    $btnClose.Add_Click({ $trafficForm.Close() })

    $panel.Controls.Add($btnRefresh)
    $panel.Controls.Add($btnOpenFile)
    $panel.Controls.Add($btnClose)

    $trafficForm.Controls.Add($grid)
    $trafficForm.Controls.Add($panel)

    [void]$trafficForm.ShowDialog($form)
}

# --- Функция создания ярлыка на рабочем столе ---
function CreateDesktopShortcut {
    try {
        $targetFile = $script:appPath
        $desktopPath = [Environment]::GetFolderPath("Desktop")
        $shortcutPath = Join-Path $desktopPath "NetSpeed.lnk"

        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($shortcutPath)

        if ($targetFile -like "*.exe") {
            $Shortcut.TargetPath = $targetFile
            $Shortcut.Arguments = ""
            $Shortcut.WorkingDirectory = $script:appDir
            $Shortcut.IconLocation = "$targetFile,0"
        } else {
            $Shortcut.TargetPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
            $Shortcut.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$targetFile`""
            $Shortcut.WorkingDirectory = "C:\WINDOWS\System32\WindowsPowerShell\v1.0"
            $Shortcut.IconLocation = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe,0"
        }
        $Shortcut.WindowStyle = 7
        $Shortcut.Description = "NetSpeed - Монитор скорости сети"

        $Shortcut.Save()

        [System.Windows.Forms.MessageBox]::Show(
            "Ярлык успешно создан на рабочем столе!",
            "NetSpeed",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Ошибка при создании ярлыка: $($_.Exception.Message)",
            "NetSpeed - Ошибка",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
}

# --- Функция парсинга цвета из HEX ---
function ParseColor($colorInput, $defaultHexOrColor) {
    if ($colorInput -is [System.Drawing.Color]) { return $colorInput }
    if ($colorInput -and $colorInput -match "^#[0-9A-Fa-f]{6}$") {
        $r = [Convert]::ToInt32($colorInput.Substring(1, 2), 16)
        $g = [Convert]::ToInt32($colorInput.Substring(3, 2), 16)
        $b = [Convert]::ToInt32($colorInput.Substring(5, 2), 16)
        return [System.Drawing.Color]::FromArgb($r, $g, $b)
    }
    if ($defaultHexOrColor -is [System.Drawing.Color]) { return $defaultHexOrColor }
    if ($defaultHexOrColor -and $defaultHexOrColor -match "^#[0-9A-Fa-f]{6}$") {
        $r = [Convert]::ToInt32($defaultHexOrColor.Substring(1, 2), 16)
        $g = [Convert]::ToInt32($defaultHexOrColor.Substring(3, 2), 16)
        $b = [Convert]::ToInt32($defaultHexOrColor.Substring(5, 2), 16)
        return [System.Drawing.Color]::FromArgb($r, $g, $b)
    }
    return [System.Drawing.Color]::Black
}

# --- Функции форматирования скорости ---
function FormatSpeed($bytesPerSec) {
    if ($script:useBits) {
        $bitsPerSec = $bytesPerSec * 8
        if ($bitsPerSec -ge 1e9) {
            return "{0:F1} Gbps" -f ($bitsPerSec / 1e9)
        } elseif ($bitsPerSec -ge 1e6) {
            return "{0:F1} Mbps" -f ($bitsPerSec / 1e6)
        } elseif ($bitsPerSec -ge 1e3) {
            return "{0:F0} Kbps" -f ($bitsPerSec / 1e3)
        } else {
            return "{0:F0} bps" -f $bitsPerSec
        }
    } else {
        if ($bytesPerSec -ge 1048576) {
            return "{0:F1} MB/s" -f ($bytesPerSec / 1048576)
        } elseif ($bytesPerSec -ge 1024) {
            return "{0:F0} KB/s" -f ($bytesPerSec / 1024)
        } else {
            return "{0:F0} B/s" -f $bytesPerSec
        }
    }
}

function FormatSpeedForScale($bytesPerSec) {
    if ($script:useBits) {
        $bitsPerSec = $bytesPerSec * 8
        if ($bitsPerSec -ge 1e9) {
            return "{0:F1} Gbps" -f ($bitsPerSec / 1e9)
        } elseif ($bitsPerSec -ge 1e6) {
            return "{0:F1} Mbps" -f ($bitsPerSec / 1e6)
        } elseif ($bitsPerSec -ge 1e3) {
            return "{0:F0} Kbps" -f ($bitsPerSec / 1e3)
        } else {
            return "{0:F0} bps" -f $bitsPerSec
        }
    } else {
        if ($bytesPerSec -ge 1048576) {
            return "{0:F1} MB/s" -f ($bytesPerSec / 1048576)
        } elseif ($bytesPerSec -ge 1024) {
            return "{0:F0} KB/s" -f ($bytesPerSec / 1024)
        } else {
            return "{0:F0} B/s" -f $bytesPerSec
        }
    }
}

function FormatTraffic($bytes) {
    if ($bytes -ge 1073741824) {
        return "{0:F1} GB" -f ($bytes / 1073741824)
    } elseif ($bytes -ge 1048576) {
        return "{0:F1} MB" -f ($bytes / 1048576)
    } elseif ($bytes -ge 1024) {
        return "{0:F0} KB" -f ($bytes / 1024)
    } else {
        return "{0:F0} B" -f $bytes
    }
}

# --- Загрузка сохраненных настроек ---
$savedSettings = LoadSettings

# --- Применение настроек ---
if ($savedSettings) {
    $script:opacity           = if ($null -ne $savedSettings.opacity) { $savedSettings.opacity } else { $script:defaultSettings.opacity }
    $script:hoverOpacity      = if ($null -ne $savedSettings.hoverOpacity) { $savedSettings.hoverOpacity } else { $script:defaultSettings.hoverOpacity }
    $script:isPinned          = if ($null -ne $savedSettings.isPinned) { $savedSettings.isPinned } else { $script:defaultSettings.isPinned }
    $script:alwaysOnTop       = if ($null -ne $savedSettings.alwaysOnTop) { $savedSettings.alwaysOnTop } else { $script:defaultSettings.alwaysOnTop }
    $script:clickThrough      = if ($null -ne $savedSettings.clickThrough) { $savedSettings.clickThrough } else { $script:defaultSettings.clickThrough }
    $script:useBits           = if ($null -ne $savedSettings.useBits) { $savedSettings.useBits } else { $script:defaultSettings.useBits }
    $script:updateInterval    = if ($null -ne $savedSettings.updateInterval) { $savedSettings.updateInterval } else { $script:defaultSettings.updateInterval }
    $script:lineThickness     = if ($null -ne $savedSettings.lineThickness) { $savedSettings.lineThickness } else { $script:defaultSettings.lineThickness }
    $script:pixelsPerPoint    = if ($null -ne $savedSettings.pixelsPerPoint) { $savedSettings.pixelsPerPoint } else { $script:defaultSettings.pixelsPerPoint }
    $script:labelPosition     = if ($null -ne $savedSettings.labelPosition) { $savedSettings.labelPosition } else { $script:defaultSettings.labelPosition }
    $script:fontSize          = if ($null -ne $savedSettings.fontSize) { $savedSettings.fontSize } else { $script:defaultSettings.fontSize }
    $script:scaleFontSize     = if ($null -ne $savedSettings.scaleFontSize) { $savedSettings.scaleFontSize } else { $script:defaultSettings.scaleFontSize }
    $script:selectedInterface = if ($null -ne $savedSettings.selectedInterface) { $savedSettings.selectedInterface } else { $script:defaultSettings.selectedInterface }

    $script:bgColor         = ParseColor $savedSettings.bgColor $script:defaultSettings.bgColor
    $script:graphBg         = ParseColor $savedSettings.graphBg $script:defaultSettings.graphBg
    $script:gridColor       = ParseColor $savedSettings.gridColor $script:defaultSettings.gridColor
    $script:scaleTextColor  = ParseColor $savedSettings.scaleTextColor $script:defaultSettings.scaleTextColor
    $script:downloadColor   = ParseColor $savedSettings.downloadColor $script:defaultSettings.downloadColor
    $script:uploadColor     = ParseColor $savedSettings.uploadColor $script:defaultSettings.uploadColor
    $script:totalColor      = ParseColor $savedSettings.totalColor $script:defaultSettings.totalColor

    $script:showGraphTotal   = if ($null -ne $savedSettings.showGraphTotal) { $savedSettings.showGraphTotal } else { $script:defaultSettings.showGraphTotal }
    $script:showGraphDown    = if ($null -ne $savedSettings.showGraphDown)  { $savedSettings.showGraphDown }  else { $script:defaultSettings.showGraphDown }
    $script:showGraphUp      = if ($null -ne $savedSettings.showGraphUp)    { $savedSettings.showGraphUp }    else { $script:defaultSettings.showGraphUp }
    $script:showLabelTotal   = if ($null -ne $savedSettings.showLabelTotal) { $savedSettings.showLabelTotal } else { $script:defaultSettings.showLabelTotal }
    $script:showLabelDown    = if ($null -ne $savedSettings.showLabelDown)  { $savedSettings.showLabelDown }  else { $script:defaultSettings.showLabelDown }
    $script:showLabelUp      = if ($null -ne $savedSettings.showLabelUp)    { $savedSettings.showLabelUp }    else { $script:defaultSettings.showLabelUp }
    $script:showTrafficTotal = if ($null -ne $savedSettings.showTrafficTotal) { $savedSettings.showTrafficTotal } else { $script:defaultSettings.showTrafficTotal }
    $script:showTrafficDown  = if ($null -ne $savedSettings.showTrafficDown)  { $savedSettings.showTrafficDown }  else { $script:defaultSettings.showTrafficDown }
    $script:showTrafficUp    = if ($null -ne $savedSettings.showTrafficUp)    { $savedSettings.showTrafficUp }    else { $script:defaultSettings.showTrafficUp }
} else {
    $script:opacity           = $script:defaultSettings.opacity
    $script:hoverOpacity      = $script:defaultSettings.hoverOpacity
    $script:isPinned          = $script:defaultSettings.isPinned
    $script:alwaysOnTop       = $script:defaultSettings.alwaysOnTop
    $script:clickThrough      = $script:defaultSettings.clickThrough
    $script:useBits           = $script:defaultSettings.useBits
    $script:updateInterval    = $script:defaultSettings.updateInterval
    $script:lineThickness     = $script:defaultSettings.lineThickness
    $script:pixelsPerPoint    = $script:defaultSettings.pixelsPerPoint
    $script:labelPosition     = $script:defaultSettings.labelPosition
    $script:fontSize          = $script:defaultSettings.fontSize
    $script:scaleFontSize     = $script:defaultSettings.scaleFontSize
    $script:selectedInterface = $script:defaultSettings.selectedInterface

    $script:bgColor         = ParseColor $script:defaultSettings.bgColor
    $script:graphBg         = ParseColor $script:defaultSettings.graphBg
    $script:gridColor       = ParseColor $script:defaultSettings.gridColor
    $script:scaleTextColor  = ParseColor $script:defaultSettings.scaleTextColor
    $script:downloadColor   = ParseColor $script:defaultSettings.downloadColor
    $script:uploadColor     = ParseColor $script:defaultSettings.uploadColor
    $script:totalColor      = ParseColor $script:defaultSettings.totalColor

    $script:showGraphTotal   = $script:defaultSettings.showGraphTotal
    $script:showGraphDown    = $script:defaultSettings.showGraphDown
    $script:showGraphUp      = $script:defaultSettings.showGraphUp
    $script:showLabelTotal   = $script:defaultSettings.showLabelTotal
    $script:showLabelDown    = $script:defaultSettings.showLabelDown
    $script:showLabelUp      = $script:defaultSettings.showLabelUp
    $script:showTrafficTotal = $script:defaultSettings.showTrafficTotal
    $script:showTrafficDown  = $script:defaultSettings.showTrafficDown
    $script:showTrafficUp    = $script:defaultSettings.showTrafficUp
}

# --- Загрузка сохраненной истории трафика ---
LoadTrafficHistory

$script:isMouseOver      = $false
$script:isUpdatingLayout = $false

# Переменные для изменения размера
$script:isResizing          = $false
$script:resizeDirection     = ""
$script:resizeStartPoint    = $null
$script:resizeStartSize     = $null
$script:resizeStartLocation = $null
$script:borderSize          = 6
$script:graphMargin         = 1  # Отступ графика от края окна

# --- P/Invoke для Click-Through ---
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class User32 {
    [DllImport("user32.dll")]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    [DllImport("user32.dll")]
    public static extern bool DestroyIcon(IntPtr hIcon);
}
"@

# --- Инициализация формы ---
$form = New-Object System.Windows.Forms.Form
[System.Windows.Forms.Control].GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]"Instance, NonPublic").SetValue($form, $true, $null)
$form.Text = "NetSpeed"
$form.TopMost = $script:alwaysOnTop
$form.FormBorderStyle = "None"
$form.ControlBox = $false
$form.MinimumSize = New-Object System.Drawing.Size(300, 200)

# Восстанавливаем размер и позицию
$widthToUse  = if ($savedSettings -and $savedSettings.windowWidth)  { $savedSettings.windowWidth }  else { $script:defaultSettings.windowWidth }
$heightToUse = if ($savedSettings -and $savedSettings.windowHeight) { $savedSettings.windowHeight } else { $script:defaultSettings.windowHeight }
$form.Size = New-Object System.Drawing.Size($widthToUse, $heightToUse)

$posX = if ($savedSettings -and $null -ne $savedSettings.windowX) { $savedSettings.windowX } else { $script:defaultSettings.windowX }
$posY = if ($savedSettings -and $null -ne $savedSettings.windowY) { $savedSettings.windowY } else { $script:defaultSettings.windowY }

if ($posX -ne -1 -and $posY -ne -1) {
    $form.StartPosition = "Manual"
    $form.Location = New-Object System.Drawing.Point($posX, $posY)
} else {
    $form.StartPosition = "CenterScreen"
}

$form.BackColor = $script:bgColor
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.Opacity = $script:opacity
$form.ShowInTaskbar = $false

# Переменные для перемещения окна
$script:dragging = $false
$script:offsetX = 0
$script:offsetY = 0

# --- Создаем иконку в трее ---
$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Text = "NetSpeed"
$notifyIcon.Visible = $true

# Храним текущую иконку для правильного освобождения
$script:currentTrayIcon = $null
$script:lastTrayIconDl = -1
$script:lastTrayIconUl = -1

# Функция обновления иконки в трее
function UpdateTrayIcon {
    $totalDown = if ($script:historyDown.Count -gt 0) { $script:historyDown[-1] } else { 0 }
    $totalUp   = if ($script:historyUp.Count -gt 0) { $script:historyUp[-1] } else { 0 }

    # Пропускаем обновление, если данные не изменились (экономим ресурсы)
    if ($totalDown -eq $script:lastTrayIconDl -and $totalUp -eq $script:lastTrayIconUl) { return }
    $script:lastTrayIconDl = $totalDown
    $script:lastTrayIconUl = $totalUp

    $dlText = FormatSpeed $totalDown
    $ulText = FormatSpeed $totalUp

    # Создаем bitmap для иконки
    $bitmap = New-Object System.Drawing.Bitmap(16, 16)
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    # Рисуем стрелку вниз (download)
    $downBrush = New-Object System.Drawing.SolidBrush($script:downloadColor)
    $downPoints = @(
        (New-Object System.Drawing.Point(3, 2)),
        (New-Object System.Drawing.Point(6, 6)),
        (New-Object System.Drawing.Point(0, 6))
    )
    $g.FillPolygon($downBrush, $downPoints)
    $downBrush.Dispose()

    # Рисуем стрелку вверх (upload)
    $upBrush = New-Object System.Drawing.SolidBrush($script:uploadColor)
    $upPoints = @(
        (New-Object System.Drawing.Point(10, 14)),
        (New-Object System.Drawing.Point(13, 10)),
        (New-Object System.Drawing.Point(7, 10))
    )
    $g.FillPolygon($upBrush, $upPoints)
    $upBrush.Dispose()

    $g.Dispose()

    # Освобождаем старую иконку, если она существует
    if ($script:currentTrayIcon) {
        $script:currentTrayIcon.Dispose()
    }

    # Создаём новую иконку
    $hIcon = $bitmap.GetHicon()
    $script:currentTrayIcon = [System.Drawing.Icon]::FromHandle($hIcon)
    $notifyIcon.Icon = $script:currentTrayIcon

    # Освобождаем bitmap и дескриптор иконки (Icon уже создана)
    $bitmap.Dispose()
    [User32]::DestroyIcon($hIcon)

    # Обновляем текст подсказки
    $notifyIcon.Text = "NetSpeed`n$([char]0x25BC) $dlText`n$([char]0x25B2) $ulText"
}

# --- Создаем PictureBox для графика ---
$pictureBox = New-Object System.Windows.Forms.PictureBox
$pictureBox.BackColor = $script:graphBg
$form.Controls.Add($pictureBox)

# --- Создаем лейблы для значений ---
$downloadLabel = New-Object System.Windows.Forms.Label
$downloadLabel.AutoSize = $true
$downloadLabel.Font = New-Object System.Drawing.Font("Segoe UI", $script:fontSize, [System.Drawing.FontStyle]::Bold)
$downloadLabel.ForeColor = $script:downloadColor
$downloadLabel.BackColor = [System.Drawing.Color]::Transparent
$downloadLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$downloadLabel.Text = "▽ 0 B/s"
$downloadLabel.Visible = $script:showLabelDown
$form.Controls.Add($downloadLabel)

$uploadLabel = New-Object System.Windows.Forms.Label
$uploadLabel.AutoSize = $true
$uploadLabel.Font = New-Object System.Drawing.Font("Segoe UI", $script:fontSize, [System.Drawing.FontStyle]::Bold)
$uploadLabel.ForeColor = $script:uploadColor
$uploadLabel.BackColor = [System.Drawing.Color]::Transparent
$uploadLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$uploadLabel.Text = "△ 0 B/s"
$uploadLabel.Visible = $script:showLabelUp
$form.Controls.Add($uploadLabel)

$totalLabel = New-Object System.Windows.Forms.Label
$totalLabel.AutoSize = $true
$totalLabel.Font = New-Object System.Drawing.Font("Segoe UI", $script:fontSize, [System.Drawing.FontStyle]::Bold)
$totalLabel.ForeColor = $script:totalColor
$totalLabel.BackColor = [System.Drawing.Color]::Transparent
$totalLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$totalLabel.Text = "▽△ 0 B/s"
$totalLabel.Visible = $script:showLabelTotal
$form.Controls.Add($totalLabel)

# --- Лейблы для трафика ---
$trafficDownloadLabel = New-Object System.Windows.Forms.Label
$trafficDownloadLabel.AutoSize = $true
$trafficDownloadLabel.Font = New-Object System.Drawing.Font("Segoe UI", $script:fontSize, [System.Drawing.FontStyle]::Bold)
$trafficDownloadLabel.ForeColor = $script:downloadColor
$trafficDownloadLabel.BackColor = [System.Drawing.Color]::Transparent
$trafficDownloadLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$trafficDownloadLabel.Text = "▼ 0 B"
$trafficDownloadLabel.Visible = $script:showTrafficDown
$form.Controls.Add($trafficDownloadLabel)

$trafficUploadLabel = New-Object System.Windows.Forms.Label
$trafficUploadLabel.AutoSize = $true
$trafficUploadLabel.Font = New-Object System.Drawing.Font("Segoe UI", $script:fontSize, [System.Drawing.FontStyle]::Bold)
$trafficUploadLabel.ForeColor = $script:uploadColor
$trafficUploadLabel.BackColor = [System.Drawing.Color]::Transparent
$trafficUploadLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$trafficUploadLabel.Text = "▲ 0 B"
$trafficUploadLabel.Visible = $script:showTrafficUp
$form.Controls.Add($trafficUploadLabel)

$trafficTotalLabel = New-Object System.Windows.Forms.Label
$trafficTotalLabel.AutoSize = $true
$trafficTotalLabel.Font = New-Object System.Drawing.Font("Segoe UI", $script:fontSize, [System.Drawing.FontStyle]::Bold)
$trafficTotalLabel.ForeColor = $script:totalColor
$trafficTotalLabel.BackColor = [System.Drawing.Color]::Transparent
$trafficTotalLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$trafficTotalLabel.Text = "▼▲ 0 B"
$trafficTotalLabel.Visible = $script:showTrafficTotal
$form.Controls.Add($trafficTotalLabel)

# --- Функция обновления формата лейблов ---
function UpdateLabelFormat {
    $isHorizontal = ($script:labelPosition -eq 0 -or $script:labelPosition -eq 1)

    $totalDown = if ($script:historyDown.Count -gt 0) { $script:historyDown[-1] } else { 0 }
    $totalUp   = if ($script:historyUp.Count -gt 0) { $script:historyUp[-1] } else { 0 }
    $totalBoth = $totalDown + $totalUp

    $dlText = FormatSpeed $totalDown
    $ulText = FormatSpeed $totalUp
    $totalText = FormatSpeed $totalBoth

    $trafficDl = FormatTraffic $script:totalTrafficDown
    $trafficUl = FormatTraffic $script:totalTrafficUp
    $trafficTotal = FormatTraffic $script:totalTrafficBoth

    if ($isHorizontal) {
        # Горизонтальное расположение - однострочный текст
        $downloadLabel.Text = "▽ $dlText"
        $uploadLabel.Text = "△ $ulText"
        $totalLabel.Text = "▽△ $totalText"
        $trafficDownloadLabel.Text = "▼ $trafficDl"
        $trafficUploadLabel.Text = "▲ $trafficUl"
        $trafficTotalLabel.Text = "▼▲ $trafficTotal"

        $downloadLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $uploadLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $totalLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $trafficDownloadLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $trafficUploadLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $trafficTotalLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    } else {
        # Вертикальное расположение - многострочный текст
        $dlFormatted = if ($dlText -match "(\d+\.?\d*)\s+(\w+/s)") { "▽`n$($Matches[1])`n$($Matches[2])" } else { "▽`n0`nB/s" }
        $ulFormatted = if ($ulText -match "(\d+\.?\d*)\s+(\w+/s)") { "△`n$($Matches[1])`n$($Matches[2])" } else { "△`n0`nB/s" }
        $totalFormatted = if ($totalText -match "(\d+\.?\d*)\s+(\w+/s)") { "▽△`n$($Matches[1])`n$($Matches[2])" } else { "▽△`n0`nB/s" }

        $trafficDlFormatted = if ($trafficDl -match "(\d+\.?\d*)\s+(\w+)") { "▼`n$($Matches[1])`n$($Matches[2])" } else { "▼`n0`nB" }
        $trafficUlFormatted = if ($trafficUl -match "(\d+\.?\d*)\s+(\w+)") { "▲`n$($Matches[1])`n$($Matches[2])" } else { "▲`n0`nB" }
        $trafficTotalFormatted = if ($trafficTotal -match "(\d+\.?\d*)\s+(\w+)") { "▼▲`n$($Matches[1])`n$($Matches[2])" } else { "▼▲`n0`nB" }

        $downloadLabel.Text = $dlFormatted
        $uploadLabel.Text = $ulFormatted
        $totalLabel.Text = $totalFormatted
        $trafficDownloadLabel.Text = $trafficDlFormatted
        $trafficUploadLabel.Text = $trafficUlFormatted
        $trafficTotalLabel.Text = $trafficTotalFormatted

        $downloadLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $uploadLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $totalLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $trafficDownloadLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $trafficUploadLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $trafficTotalLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    }

    # Принудительно обновляем лейблы
    $downloadLabel.PerformLayout()
    $uploadLabel.PerformLayout()
    $totalLabel.PerformLayout()
    $trafficDownloadLabel.PerformLayout()
    $trafficUploadLabel.PerformLayout()
    $trafficTotalLabel.PerformLayout()
}

# --- Обновление текста лейблов ---
function UpdateSpeedLabel {
    $totalDown = if ($script:historyDown.Count -gt 0) { $script:historyDown[-1] } else { 0 }
    $totalUp   = if ($script:historyUp.Count -gt 0) { $script:historyUp[-1] } else { 0 }
    $totalBoth = $totalDown + $totalUp

    $dlText = FormatSpeed $totalDown
    $ulText = FormatSpeed $totalUp
    $totalText = FormatSpeed $totalBoth

    $trafficDl = FormatTraffic $script:totalTrafficDown
    $trafficUl = FormatTraffic $script:totalTrafficUp
    $trafficTotal = FormatTraffic $script:totalTrafficBoth

    $isHorizontal = ($script:labelPosition -eq 0 -or $script:labelPosition -eq 1)

    if ($isHorizontal) {
        # Горизонтальное расположение - однострочный текст
        $downloadLabel.Text = "▽ $dlText"
        $uploadLabel.Text = "△ $ulText"
        $totalLabel.Text = "▽△ $totalText"
        $trafficDownloadLabel.Text = "▼ $trafficDl"
        $trafficUploadLabel.Text = "▲ $trafficUl"
        $trafficTotalLabel.Text = "▼▲ $trafficTotal"
    } else {
        # Вертикальное расположение - многострочный текст
        $dlFormatted = if ($dlText -match "(\d+\.?\d*)\s+(\w+/s)") { "▽`n$($Matches[1])`n$($Matches[2])" } else { "▽`n0`nB/s" }
        $ulFormatted = if ($ulText -match "(\d+\.?\d*)\s+(\w+/s)") { "△`n$($Matches[1])`n$($Matches[2])" } else { "△`n0`nB/s" }
        $totalFormatted = if ($totalText -match "(\d+\.?\d*)\s+(\w+/s)") { "▽△`n$($Matches[1])`n$($Matches[2])" } else { "▽△`n0`nB/s" }

        $trafficDlFormatted = if ($trafficDl -match "(\d+\.?\d*)\s+(\w+)") { "▼`n$($Matches[1])`n$($Matches[2])" } else { "▼`n0`nB" }
        $trafficUlFormatted = if ($trafficUl -match "(\d+\.?\d*)\s+(\w+)") { "▲`n$($Matches[1])`n$($Matches[2])" } else { "▲`n0`nB" }
        $trafficTotalFormatted = if ($trafficTotal -match "(\d+\.?\d*)\s+(\w+)") { "▼▲`n$($Matches[1])`n$($Matches[2])" } else { "▼▲`n0`nB" }

        $downloadLabel.Text = $dlFormatted
        $uploadLabel.Text = $ulFormatted
        $totalLabel.Text = $totalFormatted
        $trafficDownloadLabel.Text = $trafficDlFormatted
        $trafficUploadLabel.Text = $trafficUlFormatted
        $trafficTotalLabel.Text = $trafficTotalFormatted
    }

    if ($script:showLabelDown) { $downloadLabel.Refresh() }
    if ($script:showLabelUp)   { $uploadLabel.Refresh() }
    if ($script:showLabelTotal){ $totalLabel.Refresh() }
    if ($script:showTrafficDown) { $trafficDownloadLabel.Refresh() }
    if ($script:showTrafficUp)   { $trafficUploadLabel.Refresh() }
    if ($script:showTrafficTotal){ $trafficTotalLabel.Refresh() }
}

# --- Функция обновления макета ---
function UpdateLayout {
    $formWidth = $form.ClientSize.Width
    $formHeight = $form.ClientSize.Height
    $margin = $script:graphMargin

    # Обновляем формат лейблов в зависимости от положения
    UpdateLabelFormat

    # Определяем размеры лейблов
    $labelWidth = 0
    $labelHeight = 0

    $visibleLabels = @()
    if ($script:showLabelDown) { $visibleLabels += $downloadLabel }
    if ($script:showLabelUp)   { $visibleLabels += $uploadLabel }
    if ($script:showLabelTotal){ $visibleLabels += $totalLabel }
    if ($script:showTrafficDown) { $visibleLabels += $trafficDownloadLabel }
    if ($script:showTrafficUp)   { $visibleLabels += $trafficUploadLabel }
    if ($script:showTrafficTotal){ $visibleLabels += $trafficTotalLabel }

    # Обновляем шрифты лейблов
    $downloadLabel.Font = New-Object System.Drawing.Font("Segoe UI", $script:fontSize, [System.Drawing.FontStyle]::Bold)
    $uploadLabel.Font = New-Object System.Drawing.Font("Segoe UI", $script:fontSize, [System.Drawing.FontStyle]::Bold)
    $totalLabel.Font = New-Object System.Drawing.Font("Segoe UI", $script:fontSize, [System.Drawing.FontStyle]::Bold)
    $trafficDownloadLabel.Font = New-Object System.Drawing.Font("Segoe UI", $script:fontSize, [System.Drawing.FontStyle]::Bold)
    $trafficUploadLabel.Font = New-Object System.Drawing.Font("Segoe UI", $script:fontSize, [System.Drawing.FontStyle]::Bold)
    $trafficTotalLabel.Font = New-Object System.Drawing.Font("Segoe UI", $script:fontSize, [System.Drawing.FontStyle]::Bold)

    # Для горизонтального расположения (сверху/снизу) используем однострочный текст
    $isHorizontal = ($script:labelPosition -eq 0 -or $script:labelPosition -eq 1)

    foreach ($l in $visibleLabels) {
        $l.PerformLayout()
        $lw = $l.PreferredWidth
        $lh = $l.PreferredHeight
        if ($lw -gt $labelWidth) { $labelWidth = $lw }
        if ($lh -gt $labelHeight) { $labelHeight = $lh }
    }

    # Добавляем отступы
    $labelPadding = 10
    $labelWidth += $labelPadding * 2
    $labelHeight += $labelPadding * 2

    # Если лейблов нет, размеры = 0
    if ($visibleLabels.Count -eq 0) {
        $labelWidth = 0
        $labelHeight = 0
    }

    # Позиционирование графика с отступом от края
    $graphX = $margin
    $graphY = $margin
    $graphWidth = $formWidth - $margin * 2
    $graphHeight = $formHeight - $margin * 2

    if ($isHorizontal) {
        # Горизонтальное расположение - лейблы в строку
        if ($visibleLabels.Count -gt 0) {
            $rowHeight = $labelHeight

            if ($script:labelPosition -eq 0) { # Сверху
                $graphY = $margin + $rowHeight
                $graphHeight = $formHeight - $margin * 2 - $rowHeight
            } else { # Снизу
                $graphHeight = $formHeight - $margin * 2 - $rowHeight
            }
        }
    } else {
        # Вертикальное расположение - лейблы в столбик
        if ($visibleLabels.Count -gt 0) {
            $colWidth = $labelWidth

            if ($script:labelPosition -eq 2) { # Слева
                $graphX = $margin + $colWidth
                $graphWidth = $formWidth - $margin * 2 - $colWidth
            } else { # Справа
                $graphWidth = $formWidth - $margin * 2 - $colWidth
            }
        }
    }

    # Устанавливаем размер и позицию PictureBox
    $pictureBox.Location = New-Object System.Drawing.Point($graphX, $graphY)
    $pictureBox.Size = New-Object System.Drawing.Size($graphWidth, $graphHeight)

    # Позиционируем лейблы
    if ($visibleLabels.Count -gt 0) {
        if ($isHorizontal) {
            # Горизонтально - в строку
            $totalWidth = 0
            foreach ($l in $visibleLabels) {
                $l.PerformLayout()
                $totalWidth += $l.PreferredWidth + $labelPadding * 2
            }
            $totalWidth += ($visibleLabels.Count - 1) * 15

            $startX = [Math]::Max(0, [int](($formWidth - $totalWidth) / 2))
            $currentX = $startX

            if ($script:labelPosition -eq 0) { # Сверху
                $centerY = [Math]::Max(0, [int](($labelHeight - $labelPadding * 2) / 2)) + $margin
                foreach ($l in $visibleLabels) {
                    $l.PerformLayout()
                    $lw = $l.PreferredWidth + $labelPadding * 2
                    $l.Location = New-Object System.Drawing.Point($currentX, $centerY)
                    $currentX += $lw + 15
                }
            } else { # Снизу
                $centerY = $formHeight - $margin - $labelHeight + [Math]::Max(0, [int](($labelHeight - $labelPadding * 2) / 2))
                foreach ($l in $visibleLabels) {
                    $l.PerformLayout()
                    $lw = $l.PreferredWidth + $labelPadding * 2
                    $l.Location = New-Object System.Drawing.Point($currentX, $centerY)
                    $currentX += $lw + 15
                }
            }
        } else {
            # Вертикально - в столбик
            $totalHeight = 0
            foreach ($l in $visibleLabels) {
                $l.PerformLayout()
                $totalHeight += $l.PreferredHeight + $labelPadding * 2
            }
            $totalHeight += ($visibleLabels.Count - 1) * 8

            $startY = [Math]::Max(0, [int](($formHeight - $totalHeight) / 2))
            $currentY = $startY

            if ($script:labelPosition -eq 2) { # Слева
                foreach ($l in $visibleLabels) {
                    $l.PerformLayout()
                    $centerX = [Math]::Max(0, [int](($labelWidth - $l.PreferredWidth) / 2)) + $margin
                    $l.Location = New-Object System.Drawing.Point($centerX, $currentY)
                    $currentY += $l.PreferredHeight + $labelPadding * 2 + 8
                }
            } else { # Справа
                $rightX = $formWidth - $margin - $labelWidth
                foreach ($l in $visibleLabels) {
                    $l.PerformLayout()
                    $centerX = $rightX + [Math]::Max(0, [int](($labelWidth - $l.PreferredWidth) / 2))
                    $l.Location = New-Object System.Drawing.Point($centerX, $currentY)
                    $currentY += $l.PreferredHeight + $labelPadding * 2 + 8
                }
            }
        }
    }

    # Принудительно перерисовываем
    $pictureBox.Refresh()
    foreach ($l in $visibleLabels) {
        $l.Refresh()
    }

    # Пересчитываем масштаб графика
    UpdateMaxValue
    DrawGraph
}

# --- Определение направления изменения размера ---
function GetResizeDirection($x, $y) {
    $w = $form.ClientSize.Width
    $h = $form.ClientSize.Height
    $border = $script:borderSize

    $right  = ($x -ge $w - $border)
    $bottom = ($y -ge $h - $border)
    $left   = ($x -le $border)
    $top    = ($y -le $border)

    if ($right -and $bottom) { return "SE" }
    if ($right -and $top)    { return "NE" }
    if ($left -and $bottom)  { return "SW" }
    if ($left -and $top)     { return "NW" }
    if ($right) { return "E" }
    if ($bottom) { return "S" }
    if ($left)   { return "W" }
    if ($top)    { return "N" }
    return ""
}

# --- Добавляем обработчики ресайза на все контролы ---
function AddResizeHandlers($control) {
    $control.Add_MouseDown({
        if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            # Получаем координаты мыши относительно формы
            if ($control -eq $form) {
                $mouseX = $_.X
                $mouseY = $_.Y
            } else {
                $mouseX = $_.X + $control.Location.X
                $mouseY = $_.Y + $control.Location.Y
            }

            # Проверяем, находится ли мышь на границе
            $direction = GetResizeDirection $mouseX $mouseY
            if ($direction -ne "") {
                if (-not $script:isPinned -and -not $script:clickThrough) {
                    $script:isResizing = $true
                    $script:resizeDirection = $direction
                    $script:resizeStartPoint = New-Object System.Drawing.Point($mouseX, $mouseY)
                    $script:resizeStartSize = $form.Size
                    $script:resizeStartLocation = $form.Location
                    $form.Cursor = [System.Windows.Forms.Cursors]::Default
                }
            } else {
                # Если не на границе - перемещаем окно
                if (-not $script:isPinned -and -not $script:clickThrough) {
                    $script:dragging = $true
                    $script:offsetX = $mouseX
                    $script:offsetY = $mouseY
                }
            }
        }
    })

    $control.Add_MouseMove({
        if ($script:isResizing -and -not $script:isPinned -and -not $script:clickThrough) {
            # Получаем координаты мыши относительно формы
            if ($control -eq $form) {
                $mouseX = $_.X
                $mouseY = $_.Y
            } else {
                $mouseX = $_.X + $control.Location.X
                $mouseY = $_.Y + $control.Location.Y
            }

            $dx = $mouseX - $script:resizeStartPoint.X
            $dy = $mouseY - $script:resizeStartPoint.Y
            $newWidth = $script:resizeStartSize.Width
            $newHeight = $script:resizeStartSize.Height
            $newX = $script:resizeStartLocation.X
            $newY = $script:resizeStartLocation.Y

            switch ($script:resizeDirection) {
                "E"  { $newWidth = $script:resizeStartSize.Width + $dx }
                "S"  { $newHeight = $script:resizeStartSize.Height + $dy }
                "SE" { $newWidth = $script:resizeStartSize.Width + $dx; $newHeight = $script:resizeStartSize.Height + $dy }
                "W"  { $newWidth = $script:resizeStartSize.Width - $dx; $newX = $script:resizeStartLocation.X + $dx }
                "N"  { $newHeight = $script:resizeStartSize.Height - $dy; $newY = $script:resizeStartLocation.Y + $dy }
                "NW" { $newWidth = $script:resizeStartSize.Width - $dx; $newX = $script:resizeStartLocation.X + $dx; $newHeight = $script:resizeStartSize.Height - $dy; $newY = $script:resizeStartLocation.Y + $dy }
                "NE" { $newWidth = $script:resizeStartSize.Width + $dx; $newHeight = $script:resizeStartSize.Height - $dy; $newY = $script:resizeStartLocation.Y + $dy }
                "SW" { $newWidth = $script:resizeStartSize.Width - $dx; $newX = $script:resizeStartLocation.X + $dx; $newHeight = $script:resizeStartSize.Height + $dy }
            }

            if ($newWidth -lt $form.MinimumSize.Width) {
                if ($script:resizeDirection -match "W") {
                    $newX = $script:resizeStartLocation.X + ($script:resizeStartSize.Width - $form.MinimumSize.Width)
                }
                $newWidth = $form.MinimumSize.Width
            }
            if ($newHeight -lt $form.MinimumSize.Height) {
                if ($script:resizeDirection -match "N") {
                    $newY = $script:resizeStartLocation.Y + ($script:resizeStartSize.Height - $form.MinimumSize.Height)
                }
                $newHeight = $form.MinimumSize.Height
            }

            $form.Size = New-Object System.Drawing.Size($newWidth, $newHeight)
            $form.Location = New-Object System.Drawing.Point($newX, $newY)
            UpdateLayout
        } elseif ($script:dragging -and -not $script:isPinned -and -not $script:clickThrough) {
            # Получаем координаты мыши относительно формы
            if ($control -eq $form) {
                $mouseX = $_.X
                $mouseY = $_.Y
            } else {
                $mouseX = $_.X + $control.Location.X
                $mouseY = $_.Y + $control.Location.Y
            }

            $newX = $form.Location.X + ($mouseX - $script:offsetX)
            $newY = $form.Location.Y + ($mouseY - $script:offsetY)
            $form.Location = New-Object System.Drawing.Point($newX, $newY)
        } else {
            # Обновляем курсор
            if (-not $script:isPinned -and -not $script:clickThrough) {
                if ($control -eq $form) {
                    $mouseX = $_.X
                    $mouseY = $_.Y
                } else {
                    $mouseX = $_.X + $control.Location.X
                    $mouseY = $_.Y + $control.Location.Y
                }

                $direction = GetResizeDirection $mouseX $mouseY
                switch ($direction) {
                    "E"  { $form.Cursor = [System.Windows.Forms.Cursors]::SizeWE }
                    "W"  { $form.Cursor = [System.Windows.Forms.Cursors]::SizeWE }
                    "N"  { $form.Cursor = [System.Windows.Forms.Cursors]::SizeNS }
                    "S"  { $form.Cursor = [System.Windows.Forms.Cursors]::SizeNS }
                    "NW" { $form.Cursor = [System.Windows.Forms.Cursors]::SizeNWSE }
                    "SE" { $form.Cursor = [System.Windows.Forms.Cursors]::SizeNWSE }
                    "NE" { $form.Cursor = [System.Windows.Forms.Cursors]::SizeNESW }
                    "SW" { $form.Cursor = [System.Windows.Forms.Cursors]::SizeNESW }
                    default {
                        if ($control -ne $form) {
                            $form.Cursor = [System.Windows.Forms.Cursors]::Default
                        }
                    }
                }
            } else {
                $form.Cursor = [System.Windows.Forms.Cursors]::Default
            }
        }
    })

    $control.Add_MouseUp({
        if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            if ($script:isResizing -or $script:dragging) {
                $script:dragging = $false
                $script:isResizing = $false
                $form.Cursor = [System.Windows.Forms.Cursors]::Default
                SaveSettings
            }
        }
    })

    $control.Add_MouseLeave({
        if (-not $script:isPinned -and -not $script:clickThrough) {
            $form.Cursor = [System.Windows.Forms.Cursors]::Default
        }
    })
}

# --- Обработчики наведения мыши для прозрачности ---
$form.Add_MouseEnter({
    $script:isMouseOver = $true
    if (-not $script:isPinned) {
        $form.Opacity = $script:hoverOpacity
    }
})

$form.Add_MouseLeave({
    $script:isMouseOver = $false
    $form.Opacity = $script:opacity
})

# --- Параметры графика ---
$rightMargin      = 65
$pixelsPerPoint   = $script:pixelsPerPoint
$maxHistoryLength = 600

$script:historyDown  = New-Object System.Collections.ArrayList
$script:historyUp    = New-Object System.Collections.ArrayList
$script:historyTotal = New-Object System.Collections.ArrayList
$script:maxValue     = 102400
$script:gridStep    = 102400

$script:interfaceStats = @{}
$script:lastSampleTime = [DateTime]::Now
$script:activeInterfaces = @()
$script:lastInterfaceCheck = [DateTime]::MinValue
$script:lastSelectedInterface = $script:selectedInterface

# --- Функция получения списка интерфейсов ---
function GetNetworkInterfaces {
    try {
        $interfaces = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | Where-Object {
            $_.OperationalStatus -eq "Up" -and $_.NetworkInterfaceType -ne "Loopback"
        }
        return $interfaces
    } catch {
        return @()
    }
}

# --- Функция получения имени интерфейса для отображения ---
function GetInterfaceDisplayName($ni) {
    $name = $ni.Name
    $desc = $ni.Description

    # Сокращаем длинные имена
    if ($desc.Length -gt 30) {
        return $desc.Substring(0, 27) + "..."
    }
    return $desc
}

# --- GDI Ресурсы (кэширование для производительности) ---
$script:gdiGridPen    = $null
$script:gdiScaleFont  = $null
$script:gdiScaleBrush = $null
$script:gdiPenUp      = $null
$script:gdiPenDown    = $null
$script:gdiPenTotal   = $null

function UpdateGdiTools {
    # Освобождаем старые ресурсы
    if ($script:gdiGridPen)   { $script:gdiGridPen.Dispose() }
    if ($script:gdiScaleFont) { $script:gdiScaleFont.Dispose() }
    if ($script:gdiScaleBrush){ $script:gdiScaleBrush.Dispose() }
    if ($script:gdiPenUp)     { $script:gdiPenUp.Dispose() }
    if ($script:gdiPenDown)   { $script:gdiPenDown.Dispose() }
    if ($script:gdiPenTotal)  { $script:gdiPenTotal.Dispose() }

    # Создаем новые на основе текущих цветов
    $script:gdiGridPen    = New-Object System.Drawing.Pen($script:gridColor, 1)
    $script:gdiScaleFont  = New-Object System.Drawing.Font("Segoe UI", $script:scaleFontSize)
    $script:gdiScaleBrush = New-Object System.Drawing.SolidBrush($script:scaleTextColor)
    $script:gdiPenUp      = New-Object System.Drawing.Pen($script:uploadColor, $script:lineThickness)
    $script:gdiPenDown    = New-Object System.Drawing.Pen($script:downloadColor, $script:lineThickness)
    $script:gdiPenTotal   = New-Object System.Drawing.Pen($script:totalColor, $script:lineThickness)
}

# --- Функция подбора масштаба ---
function GetScaleParams {
    param($peakBytes)

    # Минимум 100 KB/s или 1 Mbps для красоты
    $minPeak = if ($script:useBits) { 125000 } else { 102400 }
    $effectivePeak = [Math]::Max($peakBytes, $minPeak)

    $valToScale = if ($script:useBits) { $effectivePeak * 8 } else { $effectivePeak }

    # "Красивые" шаги для сетки (1, 2, 5, 10, 20, 25, 50...)
    $niceSteps = @(1, 2, 4, 5, 10, 20, 25, 40, 50, 100, 200, 250, 400, 500)

    # Определяем порядок величины (1, K, M, G, T)
    $base = if ($script:useBits) { 1000 } else { 1024 }
    $exp = if ($valToScale -gt 0) { [Math]::Floor([Math]::Log($valToScale, $base)) } else { 0 }
    if ($exp -lt 0) { $exp = 0 }
    $unitValue = [Math]::Pow($base, $exp)

    $normalized = $valToScale / $unitValue

    # Ищем подходящий масштаб
    foreach ($s in $niceSteps) {
        if ($s -ge $normalized) {
            $maxVal = $s * $unitValue

            # Подбираем количество делений (обычно 4 или 5)
            $divisions = if ($s % 5 -eq 0) { 5 } elseif ($s % 4 -eq 0) { 4 } else { 4 }
            $gridStep = $maxVal / $divisions

            return @{
                MaxBytes  = if ($script:useBits) { $maxVal / 8 } else { $maxVal }
                StepBytes = if ($script:useBits) { $gridStep / 8 } else { $gridStep }
            }
        }
    }

    # Если не нашли (крайний случай), берем следующий порядок
    $maxVal = 1 * [Math]::Pow($base, $exp + 1)
    return @{
        MaxBytes  = if ($script:useBits) { $maxVal / 8 } else { $maxVal }
        StepBytes = if ($script:useBits) { ($maxVal / 5) / 8 } else { $maxVal / 5 }
    }
}

# --- Обновление максимального значения ---
function UpdateMaxValue {
    $plotWidth = $pictureBox.Width - $rightMargin
    $visibleCount = if ($plotWidth -gt 0) { [Math]::Max(1, [Math]::Floor($plotWidth / $script:pixelsPerPoint)) } else { 1 }

    $peak = 0
    $count = $script:historyDown.Count
    if ($count -gt 0) {
        $startIdx = [Math]::Max(0, $count - $visibleCount)
        for ($i = $startIdx; $i -lt $count; $i++) {
            $currentMax = 0
            if ($script:showGraphDown)  { $currentMax = [Math]::Max($currentMax, $script:historyDown[$i]) }
            if ($script:showGraphUp)    { $currentMax = [Math]::Max($currentMax, $script:historyUp[$i]) }
            if ($script:showGraphTotal) { $currentMax = [Math]::Max($currentMax, $script:historyTotal[$i]) }

            if ($currentMax -gt $peak) { $peak = $currentMax }
        }
    }

    $params = GetScaleParams $peak
    $script:maxValue = $params.MaxBytes
    $script:gridStep = $params.StepBytes
}

# --- Отрисовка графика ---
function DrawGraph {
    $w = $pictureBox.Width
    $h = $pictureBox.Height
    if ($w -le 0 -or $h -le 0) { return }

    if ($pictureBox.Image) {
        $pictureBox.Image.Dispose()
        $pictureBox.Image = $null
    }

    $bitmap = New-Object System.Drawing.Bitmap($w, $h)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighSpeed
    $graphics.Clear($script:graphBg)

    $plotWidth    = $w - $rightMargin
    $topMargin    = 20
    $bottomMargin = 20
    $innerHeight  = $h - $topMargin - $bottomMargin

    if ($script:maxValue -eq 0) { $script:maxValue = 102400 }
    $step = $script:gridStep
    if ($step -le 0) { $step = 102400 }

    $gridValues = @()
    $current = 0.0
    while ($current -le $script:maxValue + 0.0001) {
        $gridValues += [Math]::Min($current, $script:maxValue)
        $current += $step
    }
    if ($gridValues.Count -gt 0 -and $gridValues[-1] -ne $script:maxValue) {
        $gridValues[-1] = $script:maxValue
    }

    foreach ($valBytes in $gridValues) {
        $y = [int]($topMargin + $innerHeight - ($valBytes * $innerHeight / $script:maxValue))
        $graphics.DrawLine($script:gdiGridPen, 0, $y, $w, $y)

        $text = FormatSpeedForScale $valBytes
        $textX = $plotWidth + 6
        $textY = [int]($y - 12)
        $graphics.DrawString($text, $script:gdiScaleFont, $script:gdiScaleBrush, $textX, $textY)
    }

    $totalPoints = $script:historyDown.Count
    if ($totalPoints -gt 1) {
        $startX = $plotWidth - ($totalPoints - 1) * $script:pixelsPerPoint

        # Общая скорость
        if ($script:showGraphTotal) {
            $pointsTotal = New-Object System.Collections.ArrayList
            for ($i = 0; $i -lt $totalPoints; $i++) {
                $x = [int]($startX + $i * $script:pixelsPerPoint)
                $val = $script:historyTotal[$i]
                $y = [int]($topMargin + $innerHeight - ($val * $innerHeight / $script:maxValue))
                $y = [Math]::Max($topMargin, [Math]::Min($h - $bottomMargin, $y))
                [void]$pointsTotal.Add((New-Object System.Drawing.Point($x, $y)))
            }
            $graphics.DrawLines($script:gdiPenTotal, $pointsTotal.ToArray())
        }

        # Отдача
        if ($script:showGraphUp) {
            $pointsUp = New-Object System.Collections.ArrayList
            for ($i = 0; $i -lt $totalPoints; $i++) {
                $x = [int]($startX + $i * $script:pixelsPerPoint)
                $val = $script:historyUp[$i]
                $y = [int]($topMargin + $innerHeight - ($val * $innerHeight / $script:maxValue))
                $y = [Math]::Max($topMargin, [Math]::Min($h - $bottomMargin, $y))
                [void]$pointsUp.Add((New-Object System.Drawing.Point($x, $y)))
            }
            $graphics.DrawLines($script:gdiPenUp, $pointsUp.ToArray())
        }

        # Загрузка
        if ($script:showGraphDown) {
            $pointsDown = New-Object System.Collections.ArrayList
            for ($i = 0; $i -lt $totalPoints; $i++) {
                $x = [int]($startX + $i * $script:pixelsPerPoint)
                $val = $script:historyDown[$i]
                $y = [int]($topMargin + $innerHeight - ($val * $innerHeight / $script:maxValue))
                $y = [Math]::Max($topMargin, [Math]::Min($h - $bottomMargin, $y))
                [void]$pointsDown.Add((New-Object System.Drawing.Point($x, $y)))
            }
            $graphics.DrawLines($script:gdiPenDown, $pointsDown.ToArray())
        }
    }

    $graphics.Dispose()
    $pictureBox.Image = $bitmap
}

# --- Таймер ---
$script:timer = $null

function RestartTimer {
    if ($script:timer) {
        $script:timer.Stop()
        $script:timer.Dispose()
    }

    $script:timer = New-Object System.Windows.Forms.Timer
    $script:timer.Interval = $script:updateInterval

    $script:timer.Add_Tick({
        $now = [DateTime]::Now
        $nowDateKey = $now.ToString("yyyy-MM-dd")

        # Проверка смены суток (00:00)
        if ($nowDateKey -ne $script:currentDateKey) {
            # Сохраняем завершившийся день
            $script:trafficHistory[$script:currentDateKey] = @{
                Down = [long]$script:totalTrafficDown
                Up   = [long]$script:totalTrafficUp
            }
            SaveTrafficHistory

            # Переходим на новый день
            $script:currentDateKey = $nowDateKey
            if ($script:trafficHistory.ContainsKey($nowDateKey)) {
                $script:totalTrafficDown = [long]$script:trafficHistory[$nowDateKey].Down
                $script:totalTrafficUp   = [long]$script:trafficHistory[$nowDateKey].Up
            } else {
                $script:totalTrafficDown = 0L
                $script:totalTrafficUp   = 0L
                $script:trafficHistory[$nowDateKey] = @{ Down = 0L; Up = 0L }
            }
        }

        $timespan = ($now - $script:lastSampleTime).TotalSeconds
        if ($timespan -lt 0.1) { $timespan = 1 } # Защита от слишком частых вызовов
        $script:lastSampleTime = $now

        $currentTotalDown = 0
        $currentTotalUp   = 0

        # Получаем список интерфейсов
        $allInterfaces = GetNetworkInterfaces

        # Фильтруем интерфейсы в зависимости от выбранного
        if ($script:selectedInterface -and $script:selectedInterface -ne "") {
            $interfacesToMonitor = $allInterfaces | Where-Object { $_.Id -eq $script:selectedInterface }
        } else {
            $interfacesToMonitor = $allInterfaces
        }

        foreach ($ni in $interfacesToMonitor) {
            try {
                $stats = $ni.GetIPStatistics()
                $id = $ni.Id
                $down = $stats.BytesReceived
                $up = $stats.BytesSent

                if ($script:interfaceStats.ContainsKey($id)) {
                    $old = $script:interfaceStats[$id]
                    # Обрабатываем дельту (и возможный сброс счетчиков системой)
                    $deltaDown = if ($down -ge $old.LastDown) { $down - $old.LastDown } else { 0 }
                    $deltaUp   = if ($up -ge $old.LastUp) { $up - $old.LastUp } else { 0 }

                    $currentTotalDown += $deltaDown
                    $currentTotalUp   += $deltaUp

                    # Суммируем общий трафик за текущий день
                    $script:totalTrafficDown += $deltaDown
                    $script:totalTrafficUp   += $deltaUp
                }
                $script:interfaceStats[$id] = @{ LastDown = $down; LastUp = $up }
            } catch {}
        }

        $script:totalTrafficBoth = $script:totalTrafficDown + $script:totalTrafficUp

        # Обновляем текущие данные в истории
        $script:trafficHistory[$script:currentDateKey] = @{
            Down = [long]$script:totalTrafficDown
            Up   = [long]$script:totalTrafficUp
        }

        # Периодическое сохранение трафика (каждые ~30 секунд)
        $script:trafficSaveCounter++
        if ($script:trafficSaveCounter -ge 30) {
            $script:trafficSaveCounter = 0
            SaveTrafficHistory
        }

        # Вычисляем среднюю скорость за интервал
        $totalDown = $currentTotalDown / $timespan
        $totalUp   = $currentTotalUp / $timespan
        $totalBoth = $totalDown + $totalUp

        [void]$script:historyDown.Add($totalDown)
        [void]$script:historyUp.Add($totalUp)
        [void]$script:historyTotal.Add($totalBoth)

        # Оптимизированная очистка истории (пакетами)
        if ($script:historyDown.Count -gt ($maxHistoryLength + 20)) {
            $toRemove = $script:historyDown.Count - $maxHistoryLength
            $script:historyDown.RemoveRange(0, $toRemove)
            $script:historyUp.RemoveRange(0, $toRemove)
            $script:historyTotal.RemoveRange(0, $toRemove)
        }

        UpdateMaxValue
        UpdateSpeedLabel
        DrawGraph
        UpdateTrayIcon
    })

    $script:timer.Start()
}

# --- Click-Through ---
function ApplyClickThrough {
    $handle = $form.Handle
    $WS_EX_TRANSPARENT = 0x00000020
    $WS_EX_LAYERED     = 0x00080000
    $GWL_EXSTYLE = -20

    $currentStyle = [User32]::GetWindowLong($handle, $GWL_EXSTYLE)

    if ($script:clickThrough) {
        $newStyle = $currentStyle -bor $WS_EX_TRANSPARENT -bor $WS_EX_LAYERED
        [User32]::SetWindowLong($handle, $GWL_EXSTYLE, $newStyle)
    } else {
        $newStyle = $currentStyle -band (-bnot $WS_EX_TRANSPARENT)
        [User32]::SetWindowLong($handle, $GWL_EXSTYLE, $newStyle)
    }
}

function UpdateClickThrough {
    ApplyClickThrough
    SaveSettings
}

# --- Вспомогательные функции интерфейса ---
function ChooseColor($currentColor, $colorName) {
    $colorDialog = New-Object System.Windows.Forms.ColorDialog
    $colorDialog.Color = $currentColor
    $colorDialog.FullOpen = $true

    if ($colorDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $colorDialog.Color
    }
    return $currentColor
}

function CreateColoredBitmap($color, $size = 16) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear($color)
    $g.DrawRectangle([System.Drawing.Pens]::Black, 0, 0, $size - 1, $size - 1)
    $g.Dispose()
    return $bmp
}

function UpdateBackgroundColors {
    $form.BackColor = $script:bgColor
    $pictureBox.BackColor = $script:graphBg
    UpdateGdiTools
    DrawGraph
    UpdateSpeedLabel
}

function UpdateOpacity {
    if ($script:isMouseOver -and -not $script:isPinned) {
        $form.Opacity = $script:hoverOpacity
    } else {
        $form.Opacity = $script:opacity
    }
    SaveSettings
}

function UpdatePinState {
    if ($script:isPinned) {
        $form.Opacity = $script:opacity
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
    SaveSettings
}

# --- Добавляем обработчики ресайза ---
AddResizeHandlers $form
AddResizeHandlers $pictureBox
AddResizeHandlers $downloadLabel
AddResizeHandlers $uploadLabel
AddResizeHandlers $totalLabel
AddResizeHandlers $trafficDownloadLabel
AddResizeHandlers $trafficUploadLabel
AddResizeHandlers $trafficTotalLabel

# --- Контекстное меню ---
$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

# --- Пункт выбора интерфейса (добавлен в самое начало) ---
$interfaceMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$interfaceMenuItem.Text = "Сетевой интерфейс"

# Кнопка "Все интерфейсы"
$allInterfacesItem = New-Object System.Windows.Forms.ToolStripMenuItem
$allInterfacesItem.Text = "Все интерфейсы (суммарно)"
$allInterfacesItem.Tag = ""
$allInterfacesItem.Add_Click({
    $script:selectedInterface = ""
    UpdateMenuCheckmarks
    SaveSettings
    # Сбрасываем статистику для корректного пересчета
    $script:interfaceStats.Clear()
})
[void]$interfaceMenuItem.DropDownItems.Add($allInterfacesItem)

[void]$interfaceMenuItem.DropDownItems.Add("-")

# Функция обновления списка интерфейсов в меню
function UpdateInterfaceList {
    # Удаляем старые пункты интерфейсов (кроме "Все интерфейсы" и разделителя)
    $itemsToRemove = @()
    foreach ($item in $interfaceMenuItem.DropDownItems) {
        if ($item -is [System.Windows.Forms.ToolStripMenuItem] -and $item -ne $allInterfacesItem) {
            $itemsToRemove += $item
        }
    }
    foreach ($item in $itemsToRemove) {
        $interfaceMenuItem.DropDownItems.Remove($item)
    }

    # Получаем актуальный список интерфейсов
    $interfaces = GetNetworkInterfaces

    foreach ($ni in $interfaces) {
        $displayName = GetInterfaceDisplayName $ni
        $item = New-Object System.Windows.Forms.ToolStripMenuItem
        $item.Text = $displayName
        $item.Tag = $ni.Id
        $item.ToolTipText = $ni.Description  # Полное описание в подсказке

        $item.Add_Click({
            $script:selectedInterface = $this.Tag
            # Сбрасываем статистику для корректного пересчета
            $script:interfaceStats.Clear()
            UpdateMenuCheckmarks
            SaveSettings
        })

        [void]$interfaceMenuItem.DropDownItems.Add($item)
    }

    # Обновляем галочки
    UpdateMenuCheckmarks
}

# Статистика трафика
$trafficTableMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trafficTableMenuItem.Text = "Статистика трафика..."
$trafficTableMenuItem.Add_Click({
    ShowTrafficWindow
})

# --- Единицы измерения ---
$unitsMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$unitsMenuItem.Text = "Единицы измерения"

$bytesMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$bytesMenuItem.Text = "Байты (B/s, KB/s, MB/s)"
$bytesMenuItem.Add_Click({
    $script:useBits = $false
    UpdateMaxValue
    UpdateSpeedLabel
    DrawGraph
    UpdateMenuCheckmarks
    SaveSettings
})

$bitsMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$bitsMenuItem.Text = "Биты (bps, Kbps, Mbps)"
$bitsMenuItem.Add_Click({
    $script:useBits = $true
    UpdateMaxValue
    UpdateSpeedLabel
    DrawGraph
    UpdateMenuCheckmarks
    SaveSettings
})

[void]$unitsMenuItem.DropDownItems.Add($bytesMenuItem)
[void]$unitsMenuItem.DropDownItems.Add($bitsMenuItem)

# Интервал обновления
$intervalMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$intervalMenuItem.Text = "Интервал обновления"

$interval500ms = New-Object System.Windows.Forms.ToolStripMenuItem
$interval500ms.Text = "500 мс"
$interval500ms.Add_Click({
    $script:updateInterval = 500
    RestartTimer
    UpdateSpeedLabel
    UpdateMenuCheckmarks
    SaveSettings
})

$interval1s = New-Object System.Windows.Forms.ToolStripMenuItem
$interval1s.Text = "1 с"
$interval1s.Add_Click({
    $script:updateInterval = 1000
    RestartTimer
    UpdateSpeedLabel
    UpdateMenuCheckmarks
    SaveSettings
})

$interval5s = New-Object System.Windows.Forms.ToolStripMenuItem
$interval5s.Text = "5 с"
$interval5s.Add_Click({
    $script:updateInterval = 5000
    RestartTimer
    UpdateSpeedLabel
    UpdateMenuCheckmarks
    SaveSettings
})

[void]$intervalMenuItem.DropDownItems.Add($interval500ms)
[void]$intervalMenuItem.DropDownItems.Add($interval1s)
[void]$intervalMenuItem.DropDownItems.Add($interval5s)

# Ширина точки графика
$pixelsPerPointMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$pixelsPerPointMenuItem.Text = "Ширина точки графика"

for ($i = 1; $i -le 10; $i++) {
    $pppItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $pppItem.Text = "$i px"
    $pppItem.Tag = $i

    $pppItem.Add_Click({
        $script:pixelsPerPoint = $this.Tag
        UpdateMaxValue
        DrawGraph
        UpdateMenuCheckmarks
        SaveSettings
    })

    [void]$pixelsPerPointMenuItem.DropDownItems.Add($pppItem)
}

# Отображение графиков
$graphVisibilityMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$graphVisibilityMenuItem.Text = "Отображение графиков"

$graphTotalItem = New-Object System.Windows.Forms.ToolStripMenuItem
$graphTotalItem.Text = "▼▲ Общая"
$graphTotalItem.Add_Click({ $script:showGraphTotal = -not $script:showGraphTotal; UpdateMaxValue; DrawGraph; UpdateMenuCheckmarks; SaveSettings })

$graphDownItem = New-Object System.Windows.Forms.ToolStripMenuItem
$graphDownItem.Text = "▼ Загрузка"
$graphDownItem.Add_Click({ $script:showGraphDown = -not $script:showGraphDown; UpdateMaxValue; DrawGraph; UpdateMenuCheckmarks; SaveSettings })

$graphUpItem = New-Object System.Windows.Forms.ToolStripMenuItem
$graphUpItem.Text = "▲ Отдача"
$graphUpItem.Add_Click({ $script:showGraphUp = -not $script:showGraphUp; UpdateMaxValue; DrawGraph; UpdateMenuCheckmarks; SaveSettings })

[void]$graphVisibilityMenuItem.DropDownItems.Add($graphTotalItem)
[void]$graphVisibilityMenuItem.DropDownItems.Add($graphDownItem)
[void]$graphVisibilityMenuItem.DropDownItems.Add($graphUpItem)

# Отображение значений скорости
$labelVisibilityMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$labelVisibilityMenuItem.Text = "Отображение значений скорости"

$labelTotalItem = New-Object System.Windows.Forms.ToolStripMenuItem
$labelTotalItem.Text = "▼▲ Общая"
$labelTotalItem.Add_Click({ $script:showLabelTotal = -not $script:showLabelTotal; $totalLabel.Visible = $script:showLabelTotal; UpdateLayout; UpdateMenuCheckmarks; SaveSettings })

$labelDownItem = New-Object System.Windows.Forms.ToolStripMenuItem
$labelDownItem.Text = "▼ Загрузка"
$labelDownItem.Add_Click({ $script:showLabelDown = -not $script:showLabelDown; $downloadLabel.Visible = $script:showLabelDown; UpdateLayout; UpdateMenuCheckmarks; SaveSettings })

$labelUpItem = New-Object System.Windows.Forms.ToolStripMenuItem
$labelUpItem.Text = "▲ Отдача"
$labelUpItem.Add_Click({ $script:showLabelUp = -not $script:showLabelUp; $uploadLabel.Visible = $script:showLabelUp; UpdateLayout; UpdateMenuCheckmarks; SaveSettings })

[void]$labelVisibilityMenuItem.DropDownItems.Add($labelTotalItem)
[void]$labelVisibilityMenuItem.DropDownItems.Add($labelDownItem)
[void]$labelVisibilityMenuItem.DropDownItems.Add($labelUpItem)

# Отображение значений трафика
$trafficVisibilityMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trafficVisibilityMenuItem.Text = "Отображение значений трафика"

$trafficTotalItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trafficTotalItem.Text = "▼▲ Общий"
$trafficTotalItem.Add_Click({ $script:showTrafficTotal = -not $script:showTrafficTotal; $trafficTotalLabel.Visible = $script:showTrafficTotal; UpdateLayout; UpdateMenuCheckmarks; SaveSettings })

$trafficDownItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trafficDownItem.Text = "▼ Загрузка"
$trafficDownItem.Add_Click({ $script:showTrafficDown = -not $script:showTrafficDown; $trafficDownloadLabel.Visible = $script:showTrafficDown; UpdateLayout; UpdateMenuCheckmarks; SaveSettings })

$trafficUpItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trafficUpItem.Text = "▲ Отдача"
$trafficUpItem.Add_Click({ $script:showTrafficUp = -not $script:showTrafficUp; $trafficUploadLabel.Visible = $script:showTrafficUp; UpdateLayout; UpdateMenuCheckmarks; SaveSettings })

[void]$trafficVisibilityMenuItem.DropDownItems.Add($trafficTotalItem)
[void]$trafficVisibilityMenuItem.DropDownItems.Add($trafficDownItem)
[void]$trafficVisibilityMenuItem.DropDownItems.Add($trafficUpItem)

# Положение значений
$labelPositionMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$labelPositionMenuItem.Text = "Положение значений"

$posTopItem = New-Object System.Windows.Forms.ToolStripMenuItem
$posTopItem.Text = "Сверху (горизонтально)"
$posTopItem.Tag = 0
$posTopItem.Add_Click({ $script:labelPosition = 0; UpdateLayout; UpdateMenuCheckmarks; SaveSettings })

$posBottomItem = New-Object System.Windows.Forms.ToolStripMenuItem
$posBottomItem.Text = "Снизу (горизонтально)"
$posBottomItem.Tag = 1
$posBottomItem.Add_Click({ $script:labelPosition = 1; UpdateLayout; UpdateMenuCheckmarks; SaveSettings })

$posLeftItem = New-Object System.Windows.Forms.ToolStripMenuItem
$posLeftItem.Text = "Слева (вертикально)"
$posLeftItem.Tag = 2
$posLeftItem.Add_Click({ $script:labelPosition = 2; UpdateLayout; UpdateMenuCheckmarks; SaveSettings })

$posRightItem = New-Object System.Windows.Forms.ToolStripMenuItem
$posRightItem.Text = "Справа (вертикально)"
$posRightItem.Tag = 3
$posRightItem.Add_Click({ $script:labelPosition = 3; UpdateLayout; UpdateMenuCheckmarks; SaveSettings })

[void]$labelPositionMenuItem.DropDownItems.Add($posTopItem)
[void]$labelPositionMenuItem.DropDownItems.Add($posBottomItem)
[void]$labelPositionMenuItem.DropDownItems.Add($posLeftItem)
[void]$labelPositionMenuItem.DropDownItems.Add($posRightItem)

# Настройка цветов
$colorsMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$colorsMenuItem.Text = "Настройка цветов"

$downloadColorItem = New-Object System.Windows.Forms.ToolStripMenuItem
$downloadColorItem.Text = "Цвет загрузки (▼)"
$downloadColorItem.Image = CreateColoredBitmap $script:downloadColor
$downloadColorItem.Add_Click({
    $newColor = ChooseColor $script:downloadColor "загрузки"
    if ($newColor -ne $script:downloadColor) {
        $script:downloadColor = $newColor
        $downloadLabel.ForeColor = $script:downloadColor
        $trafficDownloadLabel.ForeColor = $script:downloadColor
        $downloadColorItem.Image = CreateColoredBitmap $script:downloadColor
        UpdateGdiTools
        DrawGraph
        SaveSettings
    }
})

$uploadColorItem = New-Object System.Windows.Forms.ToolStripMenuItem
$uploadColorItem.Text = "Цвет отдачи (▲)"
$uploadColorItem.Image = CreateColoredBitmap $script:uploadColor
$uploadColorItem.Add_Click({
    $newColor = ChooseColor $script:uploadColor "отдачи"
    if ($newColor -ne $script:uploadColor) {
        $script:uploadColor = $newColor
        $uploadLabel.ForeColor = $script:uploadColor
        $trafficUploadLabel.ForeColor = $script:uploadColor
        $uploadColorItem.Image = CreateColoredBitmap $script:uploadColor
        UpdateGdiTools
        DrawGraph
        SaveSettings
    }
})

$totalColorItem = New-Object System.Windows.Forms.ToolStripMenuItem
$totalColorItem.Text = "Цвет суммы (▼▲)"
$totalColorItem.Image = CreateColoredBitmap $script:totalColor
$totalColorItem.Add_Click({
    $newColor = ChooseColor $script:totalColor "суммарной скорости"
    if ($newColor -ne $script:totalColor) {
        $script:totalColor = $newColor
        $totalLabel.ForeColor = $script:totalColor
        $trafficTotalLabel.ForeColor = $script:totalColor
        $totalColorItem.Image = CreateColoredBitmap $script:totalColor
        UpdateGdiTools
        DrawGraph
        SaveSettings
    }
})

$bgColorItem = New-Object System.Windows.Forms.ToolStripMenuItem
$bgColorItem.Text = "Цвет фона окна"
$bgColorItem.Image = CreateColoredBitmap $script:bgColor
$bgColorItem.Add_Click({
    $newColor = ChooseColor $script:bgColor "фона окна"
    if ($newColor -ne $script:bgColor) {
        $script:bgColor = $newColor
        $bgColorItem.Image = CreateColoredBitmap $script:bgColor
        UpdateBackgroundColors
        SaveSettings
    }
})

$graphBgColorItem = New-Object System.Windows.Forms.ToolStripMenuItem
$graphBgColorItem.Text = "Цвет фона графика"
$graphBgColorItem.Image = CreateColoredBitmap $script:graphBg
$graphBgColorItem.Add_Click({
    $newColor = ChooseColor $script:graphBg "фона графика"
    if ($newColor -ne $script:graphBg) {
        $script:graphBg = $newColor
        $graphBgColorItem.Image = CreateColoredBitmap $script:graphBg
        UpdateBackgroundColors
        SaveSettings
    }
})

$gridColorItem = New-Object System.Windows.Forms.ToolStripMenuItem
$gridColorItem.Text = "Цвет линий сетки"
$gridColorItem.Image = CreateColoredBitmap $script:gridColor
$gridColorItem.Add_Click({
    $newColor = ChooseColor $script:gridColor "линий сетки"
    if ($newColor -ne $script:gridColor) {
        $script:gridColor = $newColor
        $gridColorItem.Image = CreateColoredBitmap $script:gridColor
        UpdateGdiTools
        DrawGraph
        SaveSettings
    }
})

$scaleTextColorItem = New-Object System.Windows.Forms.ToolStripMenuItem
$scaleTextColorItem.Text = "Цвет текста шкалы"
$scaleTextColorItem.Image = CreateColoredBitmap $script:scaleTextColor
$scaleTextColorItem.Add_Click({
    $newColor = ChooseColor $script:scaleTextColor "текста шкалы"
    if ($newColor -ne $script:scaleTextColor) {
        $script:scaleTextColor = $newColor
        $scaleTextColorItem.Image = CreateColoredBitmap $script:scaleTextColor
        UpdateGdiTools
        DrawGraph
        SaveSettings
    }
})

$resetColorsItem = New-Object System.Windows.Forms.ToolStripMenuItem
$resetColorsItem.Text = "Сбросить цвета по умолчанию"
$resetColorsItem.Add_Click({
    $script:downloadColor  = ParseColor $script:defaultSettings.downloadColor
    $script:uploadColor    = ParseColor $script:defaultSettings.uploadColor
    $script:totalColor     = ParseColor $script:defaultSettings.totalColor
    $script:bgColor        = ParseColor $script:defaultSettings.bgColor
    $script:graphBg        = ParseColor $script:defaultSettings.graphBg
    $script:gridColor      = ParseColor $script:defaultSettings.gridColor
    $script:scaleTextColor = ParseColor $script:defaultSettings.scaleTextColor

    $downloadLabel.ForeColor = $script:downloadColor
    $uploadLabel.ForeColor   = $script:uploadColor
    $trafficDownloadLabel.ForeColor = $script:downloadColor
    $trafficUploadLabel.ForeColor   = $script:uploadColor
    $totalLabel.ForeColor = $script:totalColor
    $trafficTotalLabel.ForeColor = $script:totalColor
    $downloadColorItem.Image = CreateColoredBitmap $script:downloadColor
    $uploadColorItem.Image   = CreateColoredBitmap $script:uploadColor
    $totalColorItem.Image    = CreateColoredBitmap $script:totalColor
    $bgColorItem.Image       = CreateColoredBitmap $script:bgColor
    $graphBgColorItem.Image  = CreateColoredBitmap $script:graphBg
    $gridColorItem.Image     = CreateColoredBitmap $script:gridColor
    $scaleTextColorItem.Image = CreateColoredBitmap $script:scaleTextColor

    UpdateBackgroundColors
    SaveSettings
})

[void]$colorsMenuItem.DropDownItems.Add($downloadColorItem)
[void]$colorsMenuItem.DropDownItems.Add($uploadColorItem)
[void]$colorsMenuItem.DropDownItems.Add($totalColorItem)
[void]$colorsMenuItem.DropDownItems.Add("-")
[void]$colorsMenuItem.DropDownItems.Add($bgColorItem)
[void]$colorsMenuItem.DropDownItems.Add($graphBgColorItem)
[void]$colorsMenuItem.DropDownItems.Add($gridColorItem)
[void]$colorsMenuItem.DropDownItems.Add($scaleTextColorItem)
[void]$colorsMenuItem.DropDownItems.Add("-")
[void]$colorsMenuItem.DropDownItems.Add($resetColorsItem)

# Толщина линий графика
$lineThicknessMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$lineThicknessMenuItem.Text = "Толщина линий графика"

for ($i = 1; $i -le 5; $i++) {
    $thicknessItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $thicknessItem.Text = "$i px"
    $thicknessItem.Tag = $i

    $thicknessItem.Add_Click({
        $script:lineThickness = $this.Tag
        UpdateGdiTools
        DrawGraph
        UpdateMenuCheckmarks
        SaveSettings
    })

    [void]$lineThicknessMenuItem.DropDownItems.Add($thicknessItem)
}

# Размер шрифта значений
$fontSizeMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$fontSizeMenuItem.Text = "Размер шрифта значений"

for ($i = 8; $i -le 20; $i += 2) {
    $fontItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $fontItem.Text = "$i pt"
    $fontItem.Tag = $i

    $fontItem.Add_Click({
        $script:fontSize = $this.Tag
        $downloadLabel.Font = New-Object System.Drawing.Font("Segoe UI", $script:fontSize, [System.Drawing.FontStyle]::Bold)
        $uploadLabel.Font = New-Object System.Drawing.Font("Segoe UI", $script:fontSize, [System.Drawing.FontStyle]::Bold)
        $totalLabel.Font = New-Object System.Drawing.Font("Segoe UI", $script:fontSize, [System.Drawing.FontStyle]::Bold)
        $trafficDownloadLabel.Font = New-Object System.Drawing.Font("Segoe UI", $script:fontSize, [System.Drawing.FontStyle]::Bold)
        $trafficUploadLabel.Font = New-Object System.Drawing.Font("Segoe UI", $script:fontSize, [System.Drawing.FontStyle]::Bold)
        $trafficTotalLabel.Font = New-Object System.Drawing.Font("Segoe UI", $script:fontSize, [System.Drawing.FontStyle]::Bold)
        UpdateLayout
        UpdateMenuCheckmarks
        SaveSettings
    })

    [void]$fontSizeMenuItem.DropDownItems.Add($fontItem)
}

# Размер шрифта шкалы
$scaleFontSizeMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$scaleFontSizeMenuItem.Text = "Размер шрифта шкалы"

for ($i = 6; $i -le 14; $i += 2) {
    $scaleFontItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $scaleFontItem.Text = "$i pt"
    $scaleFontItem.Tag = $i

    $scaleFontItem.Add_Click({
        $script:scaleFontSize = $this.Tag
        UpdateGdiTools
        DrawGraph
        UpdateMenuCheckmarks
        SaveSettings
    })

    [void]$scaleFontSizeMenuItem.DropDownItems.Add($scaleFontItem)
}

# Прозрачность
$opacityMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$opacityMenuItem.Text = "Прозрачность"

for ($i = 100; $i -ge 10; $i -= 10) {
    $opacityItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $opacityItem.Text = "$i%"
    $opacityItem.Tag = $i / 100

    $opacityItem.Add_Click({
        $script:opacity = $this.Tag
        UpdateOpacity
        UpdateMenuCheckmarks
    })

    [void]$opacityMenuItem.DropDownItems.Add($opacityItem)
}

# Прозрачность при наведении
$hoverOpacityMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$hoverOpacityMenuItem.Text = "Прозрачность при наведении"

for ($i = 100; $i -ge 10; $i -= 10) {
    $hoverItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $hoverItem.Text = "$i%"
    $hoverItem.Tag = $i / 100

    $hoverItem.Add_Click({
        $script:hoverOpacity = $this.Tag
        UpdateOpacity
        UpdateMenuCheckmarks
    })

    [void]$hoverOpacityMenuItem.DropDownItems.Add($hoverItem)
}

# Закрепить
$pinMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$pinMenuItem.Text = "Закрепить"
$pinMenuItem.Add_Click({
    $script:isPinned = -not $script:isPinned
    UpdatePinState
    UpdateMenuCheckmarks
})

# Отключить нажатия
$clickThroughMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$clickThroughMenuItem.Text = "Отключить нажатия"
$clickThroughMenuItem.Add_Click({
    $script:clickThrough = -not $script:clickThrough
    UpdateClickThrough
    UpdateMenuCheckmarks
})

# Создать ярлык
$createShortcutMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$createShortcutMenuItem.Text = "Создать ярлык"
$createShortcutMenuItem.Add_Click({
    CreateDesktopShortcut
})

# Выход
$exitMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$exitMenuItem.Text = "Выход"
$exitMenuItem.Add_Click({
    SaveTrafficHistory
    SaveSettings
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    $form.Close()
})

# Добавляем пункты в контекстное меню
[void]$contextMenu.Items.Add($interfaceMenuItem)
[void]$contextMenu.Items.Add($trafficTableMenuItem)
[void]$contextMenu.Items.Add("-")
[void]$contextMenu.Items.Add($unitsMenuItem)
[void]$contextMenu.Items.Add($intervalMenuItem)
[void]$contextMenu.Items.Add($pixelsPerPointMenuItem)
[void]$contextMenu.Items.Add("-")
[void]$contextMenu.Items.Add($graphVisibilityMenuItem)
[void]$contextMenu.Items.Add($labelVisibilityMenuItem)
[void]$contextMenu.Items.Add($trafficVisibilityMenuItem)
[void]$contextMenu.Items.Add($labelPositionMenuItem)
[void]$contextMenu.Items.Add("-")
[void]$contextMenu.Items.Add($colorsMenuItem)
[void]$contextMenu.Items.Add($lineThicknessMenuItem)
[void]$contextMenu.Items.Add($fontSizeMenuItem)
[void]$contextMenu.Items.Add($scaleFontSizeMenuItem)
[void]$contextMenu.Items.Add("-")
[void]$contextMenu.Items.Add($opacityMenuItem)
[void]$contextMenu.Items.Add($hoverOpacityMenuItem)
[void]$contextMenu.Items.Add($pinMenuItem)
[void]$contextMenu.Items.Add($clickThroughMenuItem)
[void]$contextMenu.Items.Add("-")
[void]$contextMenu.Items.Add($createShortcutMenuItem)
[void]$contextMenu.Items.Add($exitMenuItem)

function UpdateMenuCheckmarks {
    # Интерфейсы
    $allInterfacesItem.Checked = ([string]::IsNullOrEmpty($script:selectedInterface))
    foreach ($item in $interfaceMenuItem.DropDownItems) {
        if ($item -is [System.Windows.Forms.ToolStripMenuItem] -and $item -ne $allInterfacesItem) {
            $item.Checked = ($item.Tag -eq $script:selectedInterface)
        }
    }

    $bytesMenuItem.Checked = (-not $script:useBits)
    $bitsMenuItem.Checked  = $script:useBits

    $interval500ms.Checked = ($script:updateInterval -eq 500)
    $interval1s.Checked    = ($script:updateInterval -eq 1000)
    $interval5s.Checked    = ($script:updateInterval -eq 5000)

    foreach ($item in $opacityMenuItem.DropDownItems) {
        if ($item -is [System.Windows.Forms.ToolStripMenuItem]) {
            $item.Checked = ($item.Tag -eq $script:opacity)
        }
    }

    foreach ($item in $hoverOpacityMenuItem.DropDownItems) {
        if ($item -is [System.Windows.Forms.ToolStripMenuItem]) {
            $item.Checked = ($item.Tag -eq $script:hoverOpacity)
        }
    }

    foreach ($item in $lineThicknessMenuItem.DropDownItems) {
        if ($item -is [System.Windows.Forms.ToolStripMenuItem]) {
            $item.Checked = ($item.Tag -eq $script:lineThickness)
        }
    }

    foreach ($item in $pixelsPerPointMenuItem.DropDownItems) {
        if ($item -is [System.Windows.Forms.ToolStripMenuItem]) {
            $item.Checked = ($item.Tag -eq $script:pixelsPerPoint)
        }
    }

    foreach ($item in $fontSizeMenuItem.DropDownItems) {
        if ($item -is [System.Windows.Forms.ToolStripMenuItem]) {
            $item.Checked = ($item.Tag -eq $script:fontSize)
        }
    }

    foreach ($item in $scaleFontSizeMenuItem.DropDownItems) {
        if ($item -is [System.Windows.Forms.ToolStripMenuItem]) {
            $item.Checked = ($item.Tag -eq $script:scaleFontSize)
        }
    }

    # Графики
    $graphTotalItem.Checked = $script:showGraphTotal
    $graphDownItem.Checked  = $script:showGraphDown
    $graphUpItem.Checked    = $script:showGraphUp

    # Лейблы скорости
    $labelTotalItem.Checked = $script:showLabelTotal
    $labelDownItem.Checked  = $script:showLabelDown
    $labelUpItem.Checked    = $script:showLabelUp

    # Лейблы трафика
    $trafficTotalItem.Checked = $script:showTrafficTotal
    $trafficDownItem.Checked  = $script:showTrafficDown
    $trafficUpItem.Checked    = $script:showTrafficUp

    # Положение значений
    $posTopItem.Checked    = ($script:labelPosition -eq 0)
    $posBottomItem.Checked = ($script:labelPosition -eq 1)
    $posLeftItem.Checked   = ($script:labelPosition -eq 2)
    $posRightItem.Checked  = ($script:labelPosition -eq 3)

    $pinMenuItem.Checked          = $script:isPinned
    $clickThroughMenuItem.Checked = $script:clickThrough
}

# Привязываем контекстное меню
$form.ContextMenuStrip = $contextMenu
$pictureBox.ContextMenuStrip = $contextMenu
$downloadLabel.ContextMenuStrip = $contextMenu
$uploadLabel.ContextMenuStrip = $contextMenu
$totalLabel.ContextMenuStrip = $contextMenu
$trafficDownloadLabel.ContextMenuStrip = $contextMenu
$trafficUploadLabel.ContextMenuStrip = $contextMenu
$trafficTotalLabel.ContextMenuStrip = $contextMenu
$notifyIcon.ContextMenuStrip = $contextMenu

# Обновляем список интерфейсов перед показом меню
$contextMenu.Add_Opening({
    UpdateInterfaceList
})

# Клик по иконке в трее
$notifyIcon.Add_Click({
    if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        if ($form.Visible) {
            $form.Hide()
        } else {
            $form.Show()
        }
    }
})

# Обработчики наведения для прозрачности
$pictureBox.Add_MouseEnter({ $script:isMouseOver = $true; UpdateOpacity })
$pictureBox.Add_MouseLeave({ $script:isMouseOver = $false; UpdateOpacity })
$downloadLabel.Add_MouseEnter({ $script:isMouseOver = $true; UpdateOpacity })
$downloadLabel.Add_MouseLeave({ $script:isMouseOver = $false; UpdateOpacity })
$uploadLabel.Add_MouseEnter({ $script:isMouseOver = $true; UpdateOpacity })
$uploadLabel.Add_MouseLeave({ $script:isMouseOver = $false; UpdateOpacity })
$totalLabel.Add_MouseEnter({ $script:isMouseOver = $true; UpdateOpacity })
$totalLabel.Add_MouseLeave({ $script:isMouseOver = $false; UpdateOpacity })
$trafficDownloadLabel.Add_MouseEnter({ $script:isMouseOver = $true; UpdateOpacity })
$trafficDownloadLabel.Add_MouseLeave({ $script:isMouseOver = $false; UpdateOpacity })
$trafficUploadLabel.Add_MouseEnter({ $script:isMouseOver = $true; UpdateOpacity })
$trafficUploadLabel.Add_MouseLeave({ $script:isMouseOver = $false; UpdateOpacity })
$trafficTotalLabel.Add_MouseEnter({ $script:isMouseOver = $true; UpdateOpacity })
$trafficTotalLabel.Add_MouseLeave({ $script:isMouseOver = $false; UpdateOpacity })

# --- Мгновенное обновление при ресайзе ---
$form.Add_Resize({
    UpdateLayout
})

# --- Закрытие формы ---
$form.Add_FormClosing({
    if ($script:timer) {
        $script:timer.Stop()
        $script:timer.Dispose()
    }

    # Освобождаем GDI ресурсы
    if ($script:gdiGridPen)   { $script:gdiGridPen.Dispose() }
    if ($script:gdiScaleFont) { $script:gdiScaleFont.Dispose() }
    if ($script:gdiScaleBrush){ $script:gdiScaleBrush.Dispose() }
    if ($script:gdiPenUp)     { $script:gdiPenUp.Dispose() }
    if ($script:gdiPenDown)   { $script:gdiPenDown.Dispose() }

    # Освобождаем иконку трея
    if ($script:currentTrayIcon) {
        $script:currentTrayIcon.Dispose()
        $script:currentTrayIcon = $null
    }

    SaveTrafficHistory
    SaveSettings
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
})

# Применяем Click-Through при запуске
if ($script:clickThrough) {
    $form.Add_Shown({
        ApplyClickThrough
    })
}

# Инициализация и запуск
UpdateGdiTools
UpdateMaxValue
DrawGraph
RestartTimer
UpdateMenuCheckmarks
UpdateLayout
UpdateInterfaceList

[void]$form.ShowDialog()
