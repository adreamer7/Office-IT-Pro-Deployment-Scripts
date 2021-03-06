$enum3 = "
using System;

namespace Microsoft.Office
{
    [FlagsAttribute]
    public enum Branches
    {
        Current=0,
        Business=1,
        Validation=2,
        FirstReleaseCurrent=3,
        FirstReleaseBusiness=4
    }
}
"
try {
Add-Type -TypeDefinition $enum3 -ErrorAction SilentlyContinue
} catch {}

$enum4 = "
using System;

namespace Microsoft.Office
{
    [FlagsAttribute]
    public enum Channel
    {
         Current=0,
         Deferred=1,
         Validation=2,
         FirstReleaseCurrent=3,
         FirstReleaseDeferred=4
    }
}
"
try {
Add-Type -TypeDefinition $enum4 -ErrorAction SilentlyContinue
} catch {}


Function Dynamic-UpdateSource {
<#
.Synopsis
Dynamically updates the ODT Configuration Xml Update Source based on the location of the computer
.DESCRIPTION
If Office Click-to-Run is installed the administrator will be prompted to confirm
uninstallation. A configuration file will be generated and used to remove all Office CTR 
products.
.PARAMETER TargetFilePath
Specifies file path and name for the resulting XML file, for example "\\comp1\folder\config.xml".  Is also the source of the XML that will be updated.
.PARAMETER LookupFilePath
Specifies the source of the csv that contains ADSites with their corresponding SourcePath, for example "\\comp1\folder\sources.csv"
.EXAMPLE
Dynamic-UpdateSource -TargetFilePath "\\comp1\folder\config.xml" -LookupFilePath "\\comp1\folder\sources.csv"
Description:
Will Dynamically set the Update Source based a list Provided
#>
    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true, Position=0)]
        [string] $ConfigurationXML = $NULL,
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [string] $TargetFilePath = $NULL,
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [string] $LookupFilePath = $NULL,
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [bool] $SourceByIP = $false,
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [bool] $IncludeUpdatePath = $false
    )

     Process{

     #get computer ADSite and IP address
     $computerADSite = "ADSite"
     $computerIPSubnet = ""
     $SourceValue = ""
     
     #add ip address and subnet mask here
     $nic = gwmi -computer . -class "win32_networkadapterconfiguration" | Where-Object {$_.defaultIPGateway -ne $null}
     $IPAddress = $nic.ipaddress | select-object -first 1
       
     
     [bool] $isInPipe = $true
     if (($PSCmdlet.MyInvocation.PipelineLength -eq 1) -or ($PSCmdlet.MyInvocation.PipelineLength -eq $PSCmdlet.MyInvocation.PipelinePosition)) {
        $isInPipe = $false
     }

     $computerADSite = [System.DirectoryServices.ActiveDirectory.ActiveDirectorySite]::GetComputerSite().Name
     

     #looks for sourcepathlookup.csv file in local directory if parameter was not entered.
     if(!$LookupFilePath){
        $LookupFilePath = GetScriptPath
        $LookupFilePath+= "\SourcePathLookup.csv"
     }

     #get csv file for "SourcePath update"
     
     $importedSource = Import-Csv -Path $LookupFilePath -Delimiter ","

     if(!$SourceByIP){    #searches by domain name first 
        foreach($imp in $importedSource){
            if($imp.ADSite -eq $computerADSite){#try to match source from the ADSite gathered from csv
                $SourceValue = $imp.source
            }
        }
        if(!$SourceValue){#if no domain is found, tries by IP
            foreach($imp in $importedSource){                          #updated to use the subnet mask of the CSV file against the computer's IP address, then compare it to the Subnet in the CSV file for a match
                [int]$subnetMaskNumbits = $imp.Subnet.ToString().Substring($imp.Subnet.ToString().IndexOf('/')+1)
                $subnetMask = CreateSubnet -SubnetMaskNumBits $subnetMaskNumbits
                $computerIPSubnet = GetSubnet -IpAddress $IPAddress -SubnetMask $subnetMask
                $computerIPSubnet += "/"
                $computerIPSubnet += ConvertSubnetMaskToNumBits -SubnetMask  $subnetMask
                if($imp.Subnet -eq $computerIPSubnet){#try to match source from the IP gathered from csv
                    $SourceValue = $imp.source
                }
            }  
        }   
     }
     else{        #uses this path if the "-SourceByIP" is set to true
            foreach($imp in $importedSource){#updated to use the subnet mask of the CSV file against the computer's IP address, then compare it to the Subnet in the CSV file for a match
                [int]$subnetMaskNumbits = $imp.Subnet.ToString().Substring($imp.Subnet.ToString().IndexOf('/')+1)
                $subnetMask = CreateSubnet -SubnetMaskNumBits $subnetMaskNumbits
                $computerIPSubnet = GetSubnet -IpAddress $IPAddress -SubnetMask $subnetMask
                $computerIPSubnet += "/"
                $computerIPSubnet += ConvertSubnetMaskToNumBits -SubnetMask  $subnetMask
                if($imp.Subnet -eq $computerIPSubnet){#try to match source from the IP gathered from csv
                    $SourceValue = $imp.source
                }
            }          
     }
     if ($SourceValue) {
        SetODTAdd -TargetFilePath $TargetFilePath -SourcePath $SourceValue
        if($IncludeUpdatePath){
            Set-ODTUpdates -TargetFilePath $TargetFilePath -UpdatePath $SourceValue
        }

     } else {
        if ($isInPipe) {
            $results = new-object PSObject[] 0;
            $Result = New-Object �TypeName PSObject 
            Add-Member -InputObject $Result -MemberType NoteProperty -Name "TargetFilePath" -Value $TargetFilePath
            $Result
        } 
     }

    }
}

Function SetODTAdd{
    Param(

        [Parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true, Position=0)]
        [string] $ConfigurationXML = $NULL,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [string] $SourcePath = $NULL,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [string] $Version,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [string] $Bitness,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [string] $TargetFilePath,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [Microsoft.Office.Branches] $Branch,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [Microsoft.Office.Channel] $Channel = "Current"

    )

    Process{
        $TargetFilePath = GetFilePath -TargetFilePath $TargetFilePath

        #Load file
        [System.XML.XMLDocument]$ConfigFile = New-Object System.XML.XMLDocument

        if ($TargetFilePath) {
           if (!(Test-Path $TargetFilePath)) {
              $TargetFilePath = GetScriptRoot + "\" + $TargetFilePath
           }
        
           $content = Get-Content $TargetFilePath
           $ConfigFile.LoadXml($content) | Out-Null
        } else {
            if ($ConfigurationXml) 
            {
              $ConfigFile.LoadXml($ConfigurationXml) | Out-Null
              $global:saveLastConfigFile = $NULL
              $global:saveLastFilePath = $NULL
            }
        }

        $global:saveLastConfigFile = $ConfigFile.OuterXml

        #Check for proper root element
        if($ConfigFile.Configuration -eq $null){
            throw $NoConfigurationElement
        }

        #Get Add element if it exists
        if($ConfigFile.Configuration.Add -eq $null){
            [System.XML.XMLElement]$AddElement=$ConfigFile.CreateElement("Add")
            $ConfigFile.Configuration.appendChild($AddElement) | Out-Null
        }

        #Set values as desired
        if($Branch -ne $null -and $Channel -eq $null){
            $Channel = ConvertBranchNameToChannelName -BranchName $Branch
        }

        if($ConfigFile.Configuration.Add -ne $null){
            if($ConfigFile.Configuration.Add.Branch -ne $null){
                $ConfigFile.Configuration.Add.RemoveAttribute("Branch")
            }
        }

        if($Channel -ne $null){
            $ConfigFile.Configuration.Add.SetAttribute("Channel", $Channel);
        }

        if($SourcePath){
            $ConfigFile.Configuration.Add.SetAttribute("SourcePath", $SourcePath) | Out-Null
        } else {
            if ($PSBoundParameters.ContainsKey('SourcePath')) {
                $ConfigFile.Configuration.Add.RemoveAttribute("SourcePath")
            }
        }

        if($Version){
            $ConfigFile.Configuration.Add.SetAttribute("Version", $Version) | Out-Null
        } else {
            if ($PSBoundParameters.ContainsKey('Version')) {
                $ConfigFile.Configuration.Add.RemoveAttribute("Version")
            }
        }

        if($Bitness){
            $ConfigFile.Configuration.Add.SetAttribute("OfficeClientEdition", $Bitness) | Out-Null
        } else {
            if ($PSBoundParameters.ContainsKey('OfficeClientEdition')) {
                $ConfigFile.Configuration.Add.RemoveAttribute("OfficeClientEdition")
            }
        }

        $ConfigFile.Save($TargetFilePath) | Out-Null
        $global:saveLastFilePath = $TargetFilePath

        if (($PSCmdlet.MyInvocation.PipelineLength -eq 1) -or `
            ($PSCmdlet.MyInvocation.PipelineLength -eq $PSCmdlet.MyInvocation.PipelinePosition)) {
            Write-Host

            Format-XML ([xml](cat $TargetFilePath)) -indent 4

            Write-Host
            Write-Host "The Office XML Configuration file has been saved to: $TargetFilePath"
        } else {
            $results = new-object PSObject[] 0;
            $Result = New-Object �TypeName PSObject 
            Add-Member -InputObject $Result -MemberType NoteProperty -Name "TargetFilePath" -Value $TargetFilePath
            Add-Member -InputObject $Result -MemberType NoteProperty -Name "SourcePath" -Value $SourcePath
            Add-Member -InputObject $Result -MemberType NoteProperty -Name "Version" -Value $Version
            Add-Member -InputObject $Result -MemberType NoteProperty -Name "Bitness" -Value $Bitness
            $Result
        }
    }

}

Function Set-ODTUpdates{
<#
.SYNOPSIS
Modifies an existing configuration xml file's updates section
.PARAMETER SourcePath
Optional.
The UpdatePath value can be set to a network, local, or HTTP path that contains a 
Click-to-Run source. Environment variables can be used for network or local paths.
SourcePath indicates the location to save the Click-to-Run installation source 
when you run the Office Deployment Tool in download mode.
SourcePath indicates the installation source path from which to install Office 
when you run the Office Deployment Tool in configure mode. If you don�t specify 
SourcePath in configure mode, Setup will look in the current folder for the Office 
source files. If the Office source files aren�t found in the current folder, Setup 
will look on Office 365 for them.
SourcePath specifies the path of the Click-to-Run Office source from which the 
App-V package will be made when you run the Office Deployment Tool in packager mode.
If you do not specify SourcePath, Setup will attempt to create an \Office\Data\... 
folder structure in the working directory from which you are running setup.exe.
.PARAMETER Version
Optional. If a Version value is not set, the Click-to-Run product installation streams 
the latest available version from the source. The default is to use the most recently 
advertised build (as defined in v32.CAB or v64.CAB at the Click-to-Run Office installation source).
Version can be set to an Office 2013 build number by using this format: X.X.X.X
.PARAMETER Bitness
Required. Specifies the edition of Click-to-Run for Office 365 product to use: 32- or 64-bit.
.PARAMETER TargetFilePath
Full file path for the file to be modified and be output to.
.PARAMETER Branch
Optional. Specifies the update branch for the product that you want to download or install.
.Example
Set-ODTAdd -SourcePath "C:\Preload\Office" -TargetFilePath "$env:Public/Documents/config.xml"
Sets config SourcePath property of the add element to C:\Preload\Office
.Example
Set-ODTAdd -SourcePath "C:\Preload\Office" -Version "15.1.2.3" -TargetFilePath "$env:Public/Documents/config.xml"
Sets config SourcePath property of the add element to C:\Preload\Office and version to 15.1.2.3
.Notes
Here is what the portion of configuration file looks like when modified by this function:
<Configuration>
  ...
  <Add SourcePath="\\server\share\" Version="15.1.2.3" OfficeClientEdition="32"> 
      ...
  </Add>
  ...
</Configuration>
#>
    Param(

        [Parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true, Position=0)]
        [string] $ConfigurationXML = $NULL,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [string] $UpdatePath = $NULL,        

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [string] $Enabled,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [string] $TargetVersion,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [string] $Deadline,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [string] $TargetFilePath,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [Microsoft.Office.Branches] $Branch = "Current"

    )

    Process{
        $TargetFilePath = GetFilePath -TargetFilePath $TargetFilePath



        #Load file
        [System.XML.XMLDocument]$ConfigFile = New-Object System.XML.XMLDocument

        if ($TargetFilePath) {
           $ConfigFile.Load($TargetFilePath) | Out-Null
        } else {
            if ($ConfigurationXml) 
            {
              $ConfigFile.LoadXml($ConfigurationXml) | Out-Null
              $global:saveLastConfigFile = $NULL
              $global:saveLastFilePath = $NULL
            }
        }

        $global:saveLastConfigFile = $ConfigFile.OuterXml

        #Check for proper root element
        if($ConfigFile.Configuration -eq $null){
            throw $NoConfigurationElement
        }

        #Get Add element if it exists
        if($ConfigFile.Configuration.Updates -eq $null){
            [System.XML.XMLElement]$AddElement=$ConfigFile.CreateElement("Updates")
            $ConfigFile.Configuration.appendChild($AddElement) | Out-Null
        }

        #Set values as desired
         $nodes = $ConfigFile.SelectNodes("/Configuration/Updates");

        foreach($node in $nodes){
 
             #Set values as desired
             if($UpdatePath){
                 $node.SetAttribute("UpdatePath", $UpdatePath) | Out-Null
             } else {
                 if ($node.HasAttribute('UpdatePath')) {
                     $node.RemoveAttribute("UpdatePath")
                 }
             }
             <#
             if([string]::IsNullOrWhiteSpace($Enabled) -eq $false){            
                 $node.SetAttribute("Enabled", $Enabled) | Out-Null
             } else {
                 if ($node.HasAttribute('Enabled')) {
                     $node.RemoveAttribute("Enabled")
                 }
             }
 
             
         
             if([string]::IsNullOrWhiteSpace($TargetVersion) -eq $false){
                 $node.SetAttribute("Version", $TargetVersion) | Out-Null
             } else {
                 if ($node.HasAttribute('TargetVersion')) {
                     $node.RemoveAttribute("TargetVersion")
                 }
             }
 
             if([string]::IsNullOrWhiteSpace($Deadline) -eq $false){
                 $node.SetAttribute("Deadline", $Deadline) | Out-Null
             } else {
                 if ($node.HasAttribute('Deadline')) {
                     $node.RemoveAttribute("Deadline")
                 }
             }
 
             if($Branch -ne $null){
                 $node.SetAttribute("Branch", $Branch);
             } else {
                 if ($node.HasAttribute('Branch')) {
                     $node.RemoveAttribute("Branch")
                 }
             }
         #>
         }
        

        

        $ConfigFile.Save($TargetFilePath) | Out-Null
        $global:saveLastFilePath = $TargetFilePath

        if (($PSCmdlet.MyInvocation.PipelineLength -eq 1) -or `
            ($PSCmdlet.MyInvocation.PipelineLength -eq $PSCmdlet.MyInvocation.PipelinePosition)) {
            Write-Host

            Format-XML ([xml](cat $TargetFilePath)) -indent 4

            Write-Host
            Write-Host "The Office XML Configuration file has been saved to: $TargetFilePath"
        } else {
            $results = new-object PSObject[] 0;
            $Result = New-Object �TypeName PSObject 
            Add-Member -InputObject $Result -MemberType NoteProperty -Name "Enabled" -Value $Enabled
            Add-Member -InputObject $Result -MemberType NoteProperty -Name "UpdatePath" -Value $UpdatePath
            Add-Member -InputObject $Result -MemberType NoteProperty -Name "TargetVersion" -Value $TargetVersion
            Add-Member -InputObject $Result -MemberType NoteProperty -Name "Deadline" -Value $Deadline
            Add-Member -InputObject $Result -MemberType NoteProperty -Name "Branch" -Value $Branch
            $Result
        }
    }

}

Function Get-ODTAdd{
<#
.SYNOPSIS
Gets the value of the Add section in the configuration file
.PARAMETER TargetFilePath
Required. Full file path for the file.
.Example
Get-ODTAdd -TargetFilePath "$env:Public\Documents\config.xml"
Returns the value of the Add section if it exists in the specified
file. 
#>
    Param(

        [Parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true, Position=0)]
        [string] $ConfigurationXML = $NULL,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [string] $TargetFilePath

    )

    Process{
        $TargetFilePath = GetFilePath -TargetFilePath $TargetFilePath

        #Load the file
        [System.XML.XMLDocument]$ConfigFile = New-Object System.XML.XMLDocument

        if ($TargetFilePath) {
           $ConfigFile.Load($TargetFilePath) | Out-Null
        } else {
            if ($ConfigurationXml) 
            {
              $ConfigFile.LoadXml($ConfigurationXml) | Out-Null
              $global:saveLastConfigFile = $NULL
              $global:saveLastFilePath = $NULL
            }
        }

        #Check that the file is properly formatted
        if($ConfigFile.Configuration -eq $null){
            throw $NoConfigurationElement
        }
        
        $ConfigFile.Configuration.GetElementsByTagName("Add") | Select OfficeClientEdition, SourcePath, Version, Branch
    }

}

Function GetFilePath() {
    Param(
       [Parameter(ValueFromPipelineByPropertyName=$true)]
       [string] $TargetFilePath
    )

    if (!($TargetFilePath)) {
        $TargetFilePath = $global:saveLastFilePath
    }  

    if (!($TargetFilePath)) {
       Write-Host "Enter the path to the XML Configuration File: " -NoNewline
       $TargetFilePath = Read-Host
    } else {
       #Write-Host "Target XML Configuration File: $TargetFilePath"
    }

    return $TargetFilePath
}

Function Format-XML ([xml]$xml, $indent=2) { 
    $StringWriter = New-Object System.IO.StringWriter 
    $XmlWriter = New-Object System.XMl.XmlTextWriter $StringWriter 
    $xmlWriter.Formatting = "indented" 
    $xmlWriter.Indentation = $Indent 
    $xml.WriteContentTo($XmlWriter) 
    $XmlWriter.Flush() 
    $StringWriter.Flush() 
    Write-Output $StringWriter.ToString() 
}

Function GetScriptPath() {
 process {
     [string]$scriptPath = "."

     if ($PSScriptRoot) {
       $scriptPath = $PSScriptRoot
     } else {
       $scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
       $scriptPath = (Get-Item -Path ".\").FullName
     }

     return $scriptPath
 }
}

 Function ConvertSubnetMaskToNumBits(){
 Param 
    ( 
        [string] 
        $SubnetMask 
    )
    $bitCounter = 0
    $octects = $SubnetMask.Split(".")
    
    foreach($octet in $octects){      #for checking number of bits used in subnet, increases counter since the mask always counts from left hand side, so 
        if([int]$octet -ge 128){               #just adding value of that slot for each bit as it reads to the right
            $bitCounter++
        }
        if([int]$octet -ge 192){
            $bitCounter++
        }
        if([int]$octet -ge 224){
            $bitCounter++
        }
        if([int]$octet -ge 240){
            $bitCounter++
        }
        if([int]$octet -ge 248){
            $bitCounter++
        }
        if([int]$octet -ge 252){
            $bitCounter++
        }
        if([int]$octet -ge 254){
            $bitCounter++
        }
        if([int]$octet -ge 255){
            $bitCounter++
        }
    }
    return $bitCounter
 }

 Function GetSubnet(){
 Param 
    ( 
        [string] 
        $SubnetMask,
        [string]
        $IpAddress
    )
    $numTotalbits = ConvertSubnetMaskToNumBits -SubnetMask $SubnetMask
    $Subnet = ""

    $octets = $IpAddress.Split(".")
    foreach($octet in $octets){
        $tempOctet = 0
        #set num bits in current octet
        $numBitsInThisOctet = 0
        if($numTotalbits -ge 8){
            $numTotalbits -= 8
            $numBitsInThisOctet = 8
        }
        else{
            if($numTotalbits -gt 0){
                $numBitsInThisOctet = $numTotalbits
                $numTotalbits = 0
            }
        }
        #end set num bits in current octet

        if($numBitsInThisOctet -gt 0){    #to find subnet, subtract value of each spot while decrementing the number of spots used in this octet
            $numBitsInThisOctet--         #it'll stop counting when the number of spots used for subnet runs out
            if([int]$octet -ge 128){
                $tempOctet += 128
                $octet -= 128
            }
        }
        if($numBitsInThisOctet -gt 0){
            $numBitsInThisOctet--
            if([int]$octet -ge 64){
                $tempOctet += 64
                $octet -= 64
            }
        }
        if($numBitsInThisOctet -gt 0){
            $numBitsInThisOctet--
            if([int]$octet -ge 32){
                $tempOctet += 32
                $octet -= 32
            }
        }
        if($numBitsInThisOctet -gt 0){
            $numBitsInThisOctet--
            if([int]$octet -ge 16){
                $tempOctet += 16
                $octet -= 16
            }
        }
        if($numBitsInThisOctet -gt 0){
            $numBitsInThisOctet--
            if([int]$octet -ge 8){
                $tempOctet += 8
                $octet -= 8
            }
        }
        if($numBitsInThisOctet -gt 0){
            $numBitsInThisOctet--
            if([int]$octet -ge 4){
                $tempOctet += 4
                $octet -= 4
            }
        }
        if($numBitsInThisOctet -gt 0){
            $numBitsInThisOctet--
            if([int]$octet -ge 2){
                $tempOctet += 2
                $octet -= 2
            }
        }
        if($numBitsInThisOctet -gt 0){
            $numBitsInThisOctet--
            if([int]$octet -ge 1){
                $tempOctet += 1
                $octet -= 1
            }
        }

        $Subnet += $tempOctet.ToString() + "."
    }
    $Subnet = $Subnet.Remove($Subnet.Length - 1, 1)

    return $Subnet
 }

 Function CreateSubnet(){
     Param 
        ( 
            [int] 
            $SubnetMaskNumBits
        )
        $SubnetMask = ""        

        for($i=1; $i -lt 5; $i++){      
        $SubnetMaskBitsInOctect = 0
        if($SubnetMaskNumBits -gt 0)
        {
            if($SubnetMaskNumBits -lt 8)
            {
                $SubnetMaskBitsInOctect = $SubnetMaskNumBits
                $SubnetMaskNumBits = 0
            }
            else
            {
                $SubnetMaskBitsInOctect = 8
                $SubnetMaskNumBits -= 8
            }
        }
        $tempSubnetOctect = 0
        if([int]$SubnetMaskBitsInOctect -eq 1){               
            $tempSubnetOctect =128
        }
        if([int]$SubnetMaskBitsInOctect -eq 2){
            $tempSubnetOctect = 192
        }
        if([int]$SubnetMaskBitsInOctect -eq 3){
            $tempSubnetOctect = 224
        }
        if([int]$SubnetMaskBitsInOctect -eq 4){
            $tempSubnetOctect = 240
        }
        if([int]$SubnetMaskBitsInOctect -eq 5){
            $tempSubnetOctect = 248
        }
        if([int]$SubnetMaskBitsInOctect -eq 6){
            $tempSubnetOctect = 252
        }
        if([int]$SubnetMaskBitsInOctect -eq 7){
            $tempSubnetOctect = 254
        }
        if([int]$SubnetMaskBitsInOctect -eq 8){
            $tempSubnetOctect = 255
        }
        if([int]$i -lt 4){
            $SubnetMask += $tempSubnetOctect.ToString() + "."
        }
        else{
            $SubnetMask += $tempSubnetOctect.ToString()
        }
    }
    return $SubnetMask
 }