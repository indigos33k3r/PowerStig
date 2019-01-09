# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

<#
    Instructions:  Use this file to add/update/delete regsitry expressions that are used accross 
    multiple technologies files that are considered commonly used.  Enure expressions are listed
    from MOST Restrive to LEAST Restrictive, similar to exception handling.  Also, ensure only
    UNIQUE Keys are used in each hashtable to prevent errors and conflicts.  Within each table there
    can be a single key for Contains, Match, and Select.  These keys match functions in the refactored
    Functions.SingleLine.ps1 script in the RegistryRule module.  Example: See Data.Office.ps1
#>
$global:SingleLineRegistryPath += [ordered]@{
    McAfeeOne = [ordered]@{
        Match    = '(HKCU|HKLM|HKEY_LOCAL_MACHINE|HKEY_CURRENT_USER)\\'
        Select   = '((HKLM|HKCU|HKEY_LOCAL_MACHINE|HKEY_CURRENT_USER).*(?=\s\(64-bit\)$)).*(\n.*$)'
    }
}

$global:SingleLineRegistryValueName += [ordered]@{
    McAfeeOne = @{
        Select = '(?<=If the value(\s*)?((for( )?)?)").*(")?((?=is.*R)|(?=does not exist))'
    }
}

$global:SingleLineRegistryValueType += [ordered]@{
    McAfeeOne   = @{
        Select = '((HKLM|HKCU|HKEY_LOCAL_MACHINE|HKEY_CURRENT_USER).*(?=\s\(64-bit\)$)).*(\n.*$)'
    }
}

$global:SingleLineRegistryValueData += [ordered]@{
    McAfeeOne   = @{
        Select = '(?<={0})(\s*)?=.*(?=(,|\())'
    }
}
