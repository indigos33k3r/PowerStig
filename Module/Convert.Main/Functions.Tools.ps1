function Compare-PowerStigXml
{
    [CmdletBinding()]
    [OutputType([psobject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $StigXmlPath,

        [Parameter()]
        [AllowNull()]
        [string]
        $StigXccdfPath,

        [Parameter()]
        [AllowNull]
        $XccdfVersion
    )

    $ruleResults = [ordered] @{
        AddedRule       = @()
        RemovedRule     = @()
        RuleTypeChange  = @()
        RuleValueChange = @()
    }

    if (-not $StigXccdfPath)
    {
        $StigXccdfPath = Get-StigXccdfPath -StigXmlPath $StigXmlPath -Version $XccdfVersion
    }
    # Get path to the temporary STIG conversion to remove later.
    $unmatchedPath = ConvertTo-PowerStigXml -Path $StigXccdfPath -IncludeRawString -Destination $env:TEMP
    $differenceStigPath = (Select-String -InputObject $unmatchedPath -Pattern "(?<=Converted Output: ).*").Matches.Value

    [xml] $newStigContent = Get-Content -Path $differenceStigPath
    [xml] $oldStigContent = Get-Content -Path $StigXmlPath

    $ruleTypes = Get-RuleType -DisaStigContent $oldStigContent.DISASTIG

    foreach ($ruleType in $ruleTypes)
    {
        foreach ($referenceRule in $oldStigContent.DISASTIG.$ruleType.Rule)
        {
            $differenceRule = $newStigContent.DISASTIG.$ruleType.Rule | Where-Object -FilterScript {$_.id -eq $referenceRule.id}
            if ($null -eq $differenceRule)
            {
                $newRuleType = Get-NewRuleType -Id $referenceRule.id -StigContent $newStigContent
                if ($null -ne $newRuleType)
                {
                    $ruleResults.RuleTypeChange += [ordered]@{
                        RuleId       = $referenceRule.Id
                        NewRuleType  = $newRuleType.RuleType
                        OldRuleType  = $referenceRule.ToString()
                        NewRawString = $newRuleType.RawString
                        OldRawString = $referenceRule.RawString
                    }
                }
            }
            else
            {
                $difference = Compare-StigRule -ReferenceRule $referenceRule -DifferenceRule $differenceRule -RuleType $ruleType

                if ($null -ne $difference)
                {
                    $difference.NewRawString = $differenceRule.RawString
                    $difference.OldRawString = $referenceRule.RawString
                    
                    Write-Verbose -Message "Rule $($differenceRule.id) has been changed."
                    $ruleResults.RuleValueChange += $difference
                }
                else
                {
                    Write-Verbose -Message "Rule $($differenceRule.id) is not changed."
                }
            }

            $oldRuleId = Get-AllStigId -StigContent $oldStigContent
            $newRuleId = Get-AllStigId -StigContent $newStigContent

            $NewAndRemovedRuleId = Get-AddedOrRemovedRuleId -NewId $newRuleId -OldId $oldRuleId

            $ruleResults.AddedRule = $NewAndRemovedRuleId.AddedRuleId
            $ruleResults.RemovedRule = $NewAndRemovedRuleId.RemovedRuleId
        }
    }

    # Remove temporary STIG conversion.
    Remove-Item -Path $differenceStigPath -Force

    return $ruleResults
}

function Compare-StigRule
{
    param
    (
        [Parameter(Mandatory = $true)]
        $ReferenceRule,

        [Parameter(Mandatory = $true)]
        $DifferenceRule,

        [Parameter(Mandatory = $true)]
        [string]
        $RuleType
    )

    $propertyNames = Get-RuleProperty -Rule $ReferenceRule
    $parameters = @{
        ReferenceRule  = $ReferenceRule
        DifferenceRule = $DifferenceRule
        PropertyName   = $propertyNames
        RuleType       = $RuleType
    }

    switch ($RuleType)
    {
        'PermissionRule'
        {
            $returnRule = Compare-NestedPropertyRule @parameters
        }
        default
        {
            $returnRule = Compare-Property @parameters
        }
    }
    
    if ($null -ne $returnRule.id)
    {
        return $returnRule
    }
    else 
    {
        $null = return
    }
}

function Get-RuleProperty
{
    param
    (
        [Parameter(Mandatory = $true)]
        $Rule
    )

    $propertyNames = (Get-Member -InputObject $Rule | Where-Object -FilterScript {$_.MemberType -eq 'Property'}).Name
    $propertyNames = $propertyNames | Where-Object -FilterScript {$_ -notin $propertiesToRemove}

    return $propertyNames
}

function Compare-Property
{
    param
    (
        [Parameter(Mandatory = $true)]
        $ReferenceRule,

        [Parameter(Mandatory = $true)]
        $DifferenceRule,

        [Parameter(Mandatory = $true)]
        [string[]]
        $PropertyName,

        [Parameter(Mandatory = $true)]
        [string]
        $RuleType
    )

    $return = [ordered] @{}

    foreach ($property in $PropertyName)
    {
        if (Test-Property -ReferenceProperty $ReferenceRule.$property -DifferenceProperty $DifferenceRule.$property)
        {
            if (-not($return.id))
            {
                $return.id = $ReferenceRule.id
                $return.RuleType = $RuleType
            }
            
            $return."Old$property" = $ReferenceRule.$property
            $return."New$property" = $DifferenceRule.$property
        }
    }

    if ($null -ne $return.id)
    {
        return $return
    }
    else 
    {
        $null = return 
    }
}

function Test-Property
{
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $ReferenceProperty,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $DifferenceProperty
    )

    if ($null -eq $ReferenceProperty -or $null -eq $DifferenceProperty)
    {
        if ($null -eq $ReferenceProperty)
        {
            $ReferenceProperty = ''
        }
        if ($null -eq $DifferenceProperty)
        {
            $DifferenceProperty = ''
        }

        $return = $ReferenceProperty -ne $DifferenceProperty
    }
    elseif ($DifferenceProperty.GetType().ToString() -eq 'System.String[]')
    {
        $return = $ReferenceProperty.ToString() -ne $DifferenceProperty
    }
    else
    {
        $return = $ReferenceProperty.ToString() -ne $DifferenceProperty.ToString()
    }

    return $return
}

function Compare-NestedPropertyRule
{
    param
    (
        [Parameter(Mandatory = $true)]
        $ReferenceRule,

        [Parameter(Mandatory = $true)]
        $DifferenceRule,

        [Parameter(Mandatory = $true)]
        [string[]]
        $PropertyName,

        [Parameter(Mandatory = $true)]
        [string]
        $RuleType
    )

    $newPropertyNames = $PropertyName | Where-Object -FilterScript {$_ -ne 'AccessControlEntry'}

    $return = Compare-Property -ReferenceRule $ReferenceRule -DifferenceRule $DifferenceRule -PropertyName $newPropertyNames -RuleType $RuleType
    $accessControlDiff = Compare-AccessControl `
        -ReferenceList $ReferenceRule.AccessControlEntry.Entry `
        -DifferenceList $DifferenceRule.AccessControlEntry.Entry

    if ($null -ne $return)
    {
        if ($null -ne $accessControlDiff)
        {
            $return.OldAccessControlList = $accessControlDiff.OldAccessControlList
            $return.NewAccessControlList = $accessControlDiff.NewAccessControlList
        }
        
        return $return
    }
    else
    {
        if ($null -ne $accessControlDiff)
        {
            $return = [ordered] @{
                id                   = $DifferenceRule.id
                RuleType             = $RuleType
                OldAccessControlList = $accessControlDiff.OldAccessControlList
                NewAccessControlList = $accessControlDiff.NewAccessControlList
            }

            return $return
        }
        else
        {
            $null = return
        }
    }
}

function Compare-AccessControl
{
    param
    (
        [Parameter(Mandatory = $true)]
        $ReferenceList,

        [Parameter(Mandatory = $true)]
        $DifferenceList
    )
    
    $returnList = [ordered]@{
        OldAccessControlList = @()
        NewAccessControlEntry = @()
    }

    foreach ($referenceEntry in $ReferenceList)
    {
        $differenceEntry = $DifferenceList | Where-Object -FilterScript {
            $_.Principal -eq $referenceEntry.Principal -and
            $_.Inheritance -eq $referenceEntry.Inheritance -and
            $_.Rights -eq $referenceEntry.Rights
        }

        if ($null -eq $differenceEntry)
        {
            $returnList.OldAccessControlList += $referenceEntry
        }
        else
        {
            if (Test-Property -ReferenceProperty $referenceEntry.ForcePrincipal -DifferenceProperty $differenceEntry.ForcePrincipal)
            {
                $returnList.OldAccessControlList += $referenceEntry
                $returnList.NewAccessControlList += $differenceEntry    

                break
            }
        }
    }

    # We tested that Reference Entries had a difference companion but nee to do the same for the Difference Entries.
    foreach ($differenceEntry in $DifferenceList)
    {
        $referenceMatch = $ReferenceList | Where-Object -FilterScript {
            $_.Principal -eq $differenceEntry.Principal -and
            $_.Inheritance -eq $differenceEntry.Inheritance -and
            $_.Rights -eq $differenceEntry.Rights
        }
        if ($null -eq $referenceMatch)
        {
            $returnList.NewAccessControlList += $differenceEntry
        }
    }

    if ($returnList.OldAccessControlList.Count -gt 0 -or $returnList.NewAccessControlList.Count -gt 0)
    {
        return $returnList
    }

    $null = return
}

function Get-AddedOrRemovedRuleId
{
    param
    (
        [Parameter(Mandatory = $true)]
        [array]
        $NewId,

        [Parameter(Mandatory = $true)]
        [array]
        $OldId
    )

    $returnId = @{
        AddedRuleId   = ($NewId | Where-Object -FilterScript {$_ -notin $OldId})
        RemovedRuleId = ($OldId | Where-Object -FilterScript {$_ -notin $NewId})
    }

    return $returnId
}

function Get-RuleType
{
    param
    (
        [Parameter(Mandatory = $true)]
        $DisaStigContent
    )

    return (Get-Member -InputObject $DisaStigContent | Where-Object -FilterScript {$_.Name -match '.*Rule'}).Name
}

function Get-NewRuleType
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Id,

        [Parameter(Mandatory = $true)]
        $StigContent
    )

    $ruleTypes = Get-RuleType -DisaStigContent $StigContent.DISASTIG

    foreach ($ruleType in $ruleTypes)
    {
        $returnRule = $StigContent.DISASTIG.$ruleType.Rule | Where-Object -FilterScript {$_.id -eq $Id}
        
        if ($null -ne $returnRule)
        {
            $returnObject = @{
                id        = $returnRule.id
                RawString = $returnRule.RawString
                RuleType  = $ruleType
            }

            return $returnObject
        }
    }

    $null = return
} 

function Get-AllStigId
{
    param
    (
        [Parameter(Mandatory = $true)]
        $StigContent
    )

    $ruleId = @()

    $ruleTypes = Get-RuleType -DisaStigContent $StigContent.DISASTIG

    foreach ($ruleType in $ruleTypes)
    {
        $ruleId += $StigContent.DISASTIG.$RuleType.Rule.Id
    }

    return $ruleId
}

function Get-StigXccdfPath
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $StigXmlPath,

        [Parameter()]
        [AllowNull()]
        $Version
    )

    $archivePath = "$script:PsScriptRoot\StigData\Archive"
    $xmlTitle = ($StigXmlPath.Split('\')[-1]).Trim('.xml')
    $xmlSplit = $xmlTitle.Split('-')
    if ($Version)
    {
        $versionSplit = $Version.Split('.')
    }
    else
    {
        $versionSplit = $xmlSplit[3].Split('.')
    }

    $stigVersion = "V$($versionSplit[0])R$($versionSplit[1])"
    $stigHash = @{
        Technology        = $xmlSplit[0]
        TechnologyRole    = $xmlSplit[1]
        TechnologyVersion = $xmlSplit[2]
    }

    switch ($stigHash)
    {
        {$PSItem.TechnologyRole -eq '2012R2'}
        {
            $directories = Get-ChildItem -Path $archivePath -Recurse | Where-Object -FilterScript {$_.Attributes -eq 'Directory'}
            $directoryPath = ($directories | Where-Object -FilterScript {$_.Parent.Name -eq "2012R2" -and $_.Name -eq $stigHash.TechnologyVersion}).FullName
            $xccdfFullName = (Get-ChildItem -Path $directoryPath | Where-Object -FilterScript {$_.Name -match ".*$stigVersion"}).FullName
            break
        }
        {$PSItem.TechnologyVersion -in $stigTitleVariations.Office}
        {
            $appName = ($stigHash.TechnologyVersion | Select-String -Pattern '\D+(?=\d)').Matches.Value
            $appYear = ($stigHash.TechnologyVersion | Select-String -Pattern '(?<=\D)\d+').Matches.Value
            $directories = Get-ChildItem -Path $archivePath -Recurse | Where-Object -FilterScript {$_.Attributes -eq 'Directory'}
            $directoryPath = ($directories | Where-Object -FilterScript {$_.Parent.Name -eq "Office" -and $_.Name -eq $appName}).FullName
            $xccdfFullName = (Get-ChildItem -Path $directoryPath | Where-Object -FilterScript {$_.Name -match ".*$appYear.*$stigVersion"}).FullName
            break
        }
        {$PSItem.TechnologyVersion -in $stigTitleVariations.Browser}
        {
            $directories = Get-ChildItem -Path $archivePath -Recurse | Where-Object -FilterScript {$_.Attributes -eq 'Directory'}
            $directoryPath = ($directories | Where-Object -FilterScript {$_.Parent.Name -eq "Browser" -and $_.Name -eq $stigHash.TechnologyVersion}).FullName
            $xccdfFullName = (Get-ChildItem -Path $directoryPath | Where-Object -FilterScript {$_.Name -match ".*$stigVersion"}).FullName
            break
        }
        {$PSItem.TechnologyVersion -in $stigTitleVariations.ActiveDirectory}
        {
            $directories = Get-ChildItem -Path $archivePath -Recurse | Where-Object -FilterScript {$_.Attributes -eq 'Directory'}
            $directoryPath = ($directories | Where-Object -FilterScript {$_.Parent.Name -eq "ActiveDirectory" -and $_.Name -eq $stigHash.TechnologyVersion}).FullName
            $xccdfFullName = (Get-ChildItem -Path $directoryPath | Where-Object -FilterScript {$_.Name -match ".*$stigVersion"}).FullName
            break
        }
        {$PSItem.Technology -eq 'SqlServer'}
        {
            $directories = Get-ChildItem -Path $archivePath -Recurse | Where-Object -FilterScript {$_.Attributes -eq 'Directory'}
            $directoryPath = ($directories | Where-Object -FilterScript {$_.Parent.Name -eq $stigHash.TechnologyRole -and $_.Name -eq $stigHash.TechnologyVersion}).FullName
            $xccdfFullName = (Get-ChildItem -Path $directoryPath | Where-Object -FilterScript {$_.Name -match ".*$stigVersion"}).FullName
            break
        }
        {$PSItem.TechnologyRole -eq '10'}
        {
            $directoryPath = (Get-ChildItem -Path $archivePath -Recurse | Where-Object -FilterScript {$_.Attributes -eq 'Directory' -and $_.Name -eq 'Windows10'}).FullName
            $xccdfFullName = (Get-ChildItem -Path $directoryPath | Where-Object -FilterScript {$_.Name -match ".*$stigVersion"}).FullName
            break
        }
        {$PSItem.TechnologyVersion -eq 'DotNet4'}
        {
            $directoryPath = (Get-ChildItem -Path $archivePath -Recurse | Where-Object -FilterScript {$_.Attributes -eq 'Directory' -and $_.Name -eq 'DotNet'}).FullName
            $xccdfFullName = (Get-ChildItem -Path $directoryPath | Where-Object -FilterScript {$_.Name -match ".*$stigVersion"}).FullName
            break
        }
        {$PSItem.TechnologyVersion -eq 'FW'}
        {
            $directories = Get-ChildItem -Path $archivePath -Recurse | Where-Object -FilterScript {$_.Attributes -eq 'Directory'}
            $directoryPath = ($directories | Where-Object -FilterScript {$_.Parent.Name -eq 'Firewall' -and $_.Name -eq $stigHash.Technology}).FullName
            $xccdfFullName = (Get-ChildItem -Path $directoryPath | Where-Object -FilterScript {$_.Name -match ".*$stigVersion"}).FullName
            break
        }
        {$PSItem.TechnologyVersion -match '.*OracleJre.*'}
        {
            $directoryPath = (Get-ChildItem -Path $archivePath -Recurse | Where-Object -FilterScript {$_.Attributes -eq 'Directory' -and $_.Name -eq 'OracleJre'}).FullName
            $xccdfFullName = (Get-ChildItem -Path $directoryPath | Where-Object -FilterScript {$_.Name -match ".*$stigVersion"}).FullName
            break
        }
    }

    if ($xccdfFullName)
    {
        return $xccdfFullName
    }

    throw -Message "Cannot find xccdf for $xmlTitle. Please verify the desired xccdf is in the 'Archive' folder."
}   