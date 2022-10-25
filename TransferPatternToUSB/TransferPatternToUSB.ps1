param(
    [string]$PatternFolder=$PSScriptRoot,
    [string[]]$StandardFiles=@(),
    [string]$WindowXAML="$PSScriptRoot\XAML\PatternListWindow.xaml"
)

Begin {
    Function Get-PatternList {
        param(
            [string]$Path=$PatternFolder
        )

        $Table = [ordered]@{}
        Get-ChildItem $Path -Filter "*.csv" | Sort-Object -Property BaseName |
             ForEach-Object { 
                $Table.($_.BaseName -replace "[_\-]"," ") = $_
            }
        $Table
    }

    Function Get-USBDrive {

        $LogicalDisks = Get-CimInstance -Namespace root/Cimv2 -ClassName 'Win32_LogicalDisk' | Where-Object { $_.Description -match "Removable" }
        If ($LogicalDisks) {
            $PSDrives = Get-PSDrive
            $USBDrives = $PSDrives | Where-Object { $_.name -in ($LogicalDisks.DeviceID.Substring(0,1)) }
            $USBDrives
        }
    }

    Function Show-PatternXamlDialog {
        param(
            $PatternList,
            [System.Management.Automation.PSDriveInfo[]]$USBDrives,
            $XamlFile=$WindowXAML
        )

        Function OkClick {
            $windowForm | Add-Member NoteProperty Result "Ok" -Force
            $windowForm.Close()
        }

        Function CancelClick {
            If ($ListBox.SelectedItem) {
                $ListBox.SelectedItem = $null
                $windowForm | Add-Member NoteProperty Result "Cancel" -Force
            } else {
                $windowForm | Add-Member NoteProperty Result "Cancel" -Force
                $windowForm.Close()
            }
        }

        Add-Type -AssemblyName PresentationFramework

        $Content = Get-Content $XamlFile -raw
        [xml]$xml = $Content
        $reader=(New-Object System.Xml.XmlNodeReader $xml)
        $windowForm=[Windows.Markup.XamlReader]::Load( $reader )
        
        $ListBox = $windowForm.FindName("ListPatterns")
        $ListBox.Items.Clear()
        $PatternList.Keys | ForEach-Object {[void] $ListBox.Items.Add($_)}
        $ListBox.SelectionMode = "Extended"

        $ComboBox = $windowForm.FindName("ComboDrives")
        $ComboBox.Items.CLear()
        $USBDrives | ForEach-Object { 
            $ItemLabel = "{0}: {1}" -f $_.Name,$_.Description
            [void]$ComboBox.Items.Add($ItemLabel)
        }
        $ComboBox.SelectedIndex = "0"

        $OkButton = $windowForm.FindName("ButtonOk")
        [System.Windows.RoutedEventHandler]$OkClickEvent = {
            param ($sender,$e)
                OkClick
            }
        $OkButton.AddHandler([System.Windows.Controls.Button]::ClickEvent,$OkClickEvent)

        $CancelButton = $windowForm.FindName("ButtonCancel")
        [System.Windows.RoutedEventHandler]$CancelClickEvent = {
            param ($sender,$e)
                CancelClick
            }
        $CancelButton.AddHandler([System.Windows.Controls.Button]::ClickEvent,$CancelClickEvent)

        $null = $windowForm.ShowDialog()

        $DialogResult = $windowForm.Result
        If ($DialogResult -eq "Ok") {
            $Drive = $USBDrives | Where-Object { $_.Name -eq ($ComboBox.SelectedItem -replace "^([^:]+):.*$","`$1")}
            [PSCustomObject]@{
                Drive = $Drive
                Form = $windowForm
                Patterns = $ListBox.SelectedItems
            }
        }
    }

    Function Read-PatternChoice {
        param(
            $PatternList,
            [System.Management.Automation.PSDriveInfo[]]$USBDrives
        )

        $Dialog = Show-PatternXamlDialog -PatternList $PatternList -USBDrives $USBDrives
        $Dialog
    }

    function Copy-PatternToUSB {
        param (
            $Pattern,
            $Drive
        )
        
        Write-Host "Copying $Pattern to $Drive"
        Copy-Item $Pattern "$($Drive):\" 
    }

    Function Set-USBLabel {
        param(
            [System.Management.Automation.PSDriveInfo]$Drive,
            [string]$CompanyLabel="Nalinu.Pink"
        )

        If ($Drive) {
            $WMIDrive = gwmi win32_volume -Filter “DriveLetter = ‘$($Drive.Name):'”
            $WMIDrive.Label = $CompanyLabel
            $WMIDrive.put()
            $Drive.Description = $CompanyLabel
        }
    }

    Function Copy-StandardFiles {
        param(
            [string]$Drive,
            [string[]]$Files=$StandardFiles
        )

        If ($Files.count -gt 0) {
            Copy-Item -Path  $Files -Destination "$($Drive):\"
        }
    }

    Function Show-CopyResult {
        param(
            [System.Management.Automation.PSDriveInfo]$Drive,
            [string]$Pattern
        )

        
    }
}

Process {

    $PatternList = Get-PatternList
    $USBDrive = @((Get-USBDrive))
    $Choice = Read-PatternChoice -PatternList $PatternList -USBDrives $USBDrive
    If ($Choice.Drive) {
        Copy-StandardFiles -Drive $Choice.Drive.Name
        Set-USBLabel -Drive ($USBDrive | Where-Object { $_.Name -eq $Choice.Drive })
    } elseif ($Choice.Patterns) {
        Write-Error "No USB Drive selected. Please try to copy again."
        Pause
        break        
    }

    ForEach ($Pattern in $Choice.Patterns) {
        Write-Host "$Pattern $($Choice.Drive.Name)"
        Copy-PatternToUSB -Pattern $PatternList.$Pattern -Drive $Choice.Drive.Name
    }

}