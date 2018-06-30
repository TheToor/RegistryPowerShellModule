Enum REG
{
    NONE
    BINARY
    DWORD
    EXPAND_SZ
    LINK
    MULTI_SZ
    QWORD
    SZ
}

Class RegFile
{
    [String]$FileName
    [String]$Path
    [RegEntry[]]$Entries

    [bool] CheckIntegrity()
    {
        foreach($entry in $this.Entries) {
            if(!$entry.CheckIntegrity()) {
                return $false
            }
        }

        return $true
    }
}

Class RegEntry
{
    [String]$Path
    [RegKey[]]$Keys

    [bool] CheckIntegrity()
    {
        $powershellPath = $this.Path.
            Replace("HKEY_LOCAL_MACHINE", "HKLM:").
            Replace("HKEY_CURRENT_USER", "HKCU:")

        foreach($key in $this.Keys) {
            if(!$key.CheckIntegrity($powershellPath)) {
                return $false
            }
        }

        return $true
    }
}

Class RegKey
{
    [String]$KeyName
    [Object]$Value
    [REG]$Type

    [bool] CheckIntegrity($basePath)
    {
        $property = Get-ItemProperty $basePath -Name $this.KeyName -ErrorAction SilentlyContinue
        if($property -eq $null) {
            #Key doesn't exist
            return $false
        }

        $currentValue = $property.$($this.KeyName)
    
        if($currentValue -ne $this.Value) {
            Write-Verbose "$($this.KeyName): $currentValue is not $($this.Value)"
            return $false
        }

        return $true
    }
}

Function Test-RegistryIntegrity {
    <#
    .SYNOPSIS
    Checks if the registry contains the keys
    .DESCRIPTION
    Compares all keys anc checks if the exist. If they exist the value is checked.
    .EXAMPLE
    $regFile = Import-RegistryFile -Path C:\temp\file.reg
    Test-RegistryIntegrity -RegFile $regFile
    .EXAMPLE
    Give another example of how to use it
    .PARAMETER example
    The computer name to query. Just one.
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(
			Mandatory=$True,
			ValueFromPipeline=$True,
			ValueFromPipelineByPropertyName=$True
		)]
        [RegFile]$regFile
    )

    Begin {
		Write-Verbose "$($MyInvocation.MyCommand) started"
    }

    Process {
        if($regFile -eq $null) {
            Write-Host "Invalid regfile"
            return $false
        }

        return $regFile.CheckIntegrity()
    }

    End {
		Write-Verbose "$($MyInvocation.MyCommand) ended"
    }
}

Function Import-RegistryFile {
    <#
    .SYNOPSIS
    Imports a .reg file
    .DESCRIPTION
    Imports a .reg file with the current user
    .EXAMPLE
    Import-RegistryFile -Path C:\temp\file.reg
    .PARAMETER Path
    The absolute or relative path to the file
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(
			Mandatory=$True,
			ValueFromPipeline=$True,
			ValueFromPipelineByPropertyName=$True
		)]
        [String[]]$path,

        [Parameter(
            Mandatory=$False,
            ValueFromPipeline=$False
        )]
        [Alias('Architecture')]
        [switch]$x86
    )

    Begin {
        Write-Verbose "$($MyInvocation.MyCommand) started"
    }

    Process {
        $fullPath = [System.IO.Path]::GetFullPath($path)
            if(!(Test-Path $fullPath)) {
            Write-Error "File $fullPath does not exist"
            return
        }

        if($x86) {
            reg import "$fullPath" /reg:32
        } else {
            reg import "$fullPath" /reg:64
        }
    }

    End {
		Write-Verbose "$($MyInvocation.MyCommand) ended"
    }
}

Function Get-RegistryFile {
    <#
    .SYNOPSIS
    Translates a .reg file into a readable powershell object
    .DESCRIPTION
    Returns a powershell object to work with the reg file
    .EXAMPLE
    Get-RegistryFile -path C:\temp\file.reg
    .PARAMETER Path
    The absolute or relative path to the file
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(
			Mandatory=$True,
			ValueFromPipeline=$True,
			ValueFromPipelineByPropertyName=$True,
			HelpMessage='The path to the .reg file'
		)]
        [String]$path
    )

    Begin {
		Write-Verbose "$($MyInvocation.MyCommand) started"
    }

    Process {
         $fullPath = [System.IO.Path]::GetFullPath($path)
         if(!(Test-Path $fullPath)) {
            Write-Error "File $fullPath does not exist"
            return $null
         }
         
         $regFile = New-Object RegFile
         $regFile.Path = $fullPath
         $regFile.FileName = [System.IO.Path]::GetFileName($fullPath)
         
         [RegEntry]$currentEntry = $null
         [RegKey]$currentKey = $null
         [bool]$multiLine = $False

         Switch -Regex -File $fullPath
         {
            "^\[(.+)\]$" # Section
            {
                Write-Verbose "Section Match: $($matches[1])"

                $currentEntry = New-Object RegEntry
                $currentEntry.Path = $matches[1]

                $regFile.Entries += $currentEntry
            }

            "(.+?)\s*=\s*(.*)" # Key
            {  
                if (!($currentEntry))
                {
                    Write-Error "Matched a key before section. Invalid reg file?"
                    return $null
                }

                Write-Verbose "Key Match: $($matches[1]): $($matches[2])"

                $split = $matches[2] -split ':',2
                if($split.Length -eq 2) {
                    $type = $split[0] -replace "\(.*\)", ""
                    $value = $split[1]
                } else {
                    $type = "string"
                    $value = $split[0]
                }

                $keyName = $matches[1].SubString(1, $matches[1].Length - 2)
                if($value.StartsWith('"')) {
                    $value = $value.SubString(1, $value.Length - 1)
                }
                if($value.EndsWith('"')) {
                    $value = $value.SubString(0, $value.Length - 1)
                }
               
                $currentKey = New-Object RegKey
                $currentKey.KeyName = $keyName
                $currentKey.Value = $value
                
                switch ($type)
                {
                    "string" {
                        $currentKey.Type = [REG]::SZ
                    }

                    "dword" {
                        $currentKey.Type = [REG]::DWORD
                    }

                    "hex" {
                        $currentKey.Type = [REG]::BINARY
                    }

                    default {
                        #Invalid key name -> maybe a wrong split
                        #Lets revert the split
                        Write-Verbose "Invalid type: $type"
                        $currentKey.Type = [REG]::SZ
                        $currentKey.Value = $matches[2]
                    }
                }

                $currentEntry.Keys += $currentKey

                if($value.Trim().EndsWith("\")) {
                    $multiLine = $True
                }

                Continue
            }
            
            ".*\\$" #Multi-Line
            {
                if(!($currentKey))
                {
                    Write-Error "Matched a multi line before the key itself"
                    return $null
                }

                Write-Verbose "Matched Multi-Line: $($matches[0])"

                $currentKey.Value = $currentKey.Value.TrimEnd().SubString(0, $currentKey.Value.Length - 1)
                $currentKey.Value += $matches[0].Trim()

                $multiLine = $True

                Continue
            }

            ".*$" #End-Multiline
            {
                if(!$multiLine) {
                    continue
                }

                if(!($currentKey))
                {
                    Write-Error "Matched a end of multi line before the key itself"
                    return $null
                }

                Write-Verbose "Matched end of Multi-Line: $($matches[0])"

                $currentKey.Value = $currentKey.Value.TrimEnd().SubString(0, $currentKey.Value.Length - 1)
                $currentKey.Value += $matches[0].Trim()

                $multiLine = $False
            }
         }

         return $regFile
    }

    End {
		Write-Verbose "$($MyInvocation.MyCommand) ended"
    }
}

Export-ModuleMember -Function 'Import-RegistryFile'
Export-ModuleMember -Function 'Get-RegistryFile'
Export-ModuleMember -Function 'Test-RegistryIntegrity'