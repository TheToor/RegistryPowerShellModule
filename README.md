# RegistryPowerShellModule

> A simple PowerShell Module to work with .reg files

> Adds the following functions:
- Import-RegistryFile
- Get-RegistryFile
- Test-RegistryIntegrity

> The module was created to simply verify if a reg file should be imported or not
> Can be used in SCCM and similar software for baselines to verify settings
---

## Example

```powershell
Import-Module Registry

$file = Get-RegistryFile -Path C:\temp\file.reg
if(!(Test-RegistryIntegrity $file)) {
	Import-RegistryFile -Path C:\temp\file.reg
}
```