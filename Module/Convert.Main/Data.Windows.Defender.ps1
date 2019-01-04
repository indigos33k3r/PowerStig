# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

<#
    Instructions:  Use this file to add/update/delete regsitry expressions that are used accross 
    Windows Defender files.  Ensure expressions are listed from MOST Restrive to LEAST Restrictive, 
    similar to exception handling.  Also, ensure only UNIQUE Keys are used in each hashtable to 
    prevent errors and conflicts.
#>

$global:SingleLineRegistryValueName += [ordered]@{
    # Added for Windows Defender Stig rule V-75153
    Defender2 = @{
        Select = '(?<=If the value\s")(.*)(?=does not exist)'
    }
}

$global:SingleLineRegistryValueData += [ordered]@{
    # Added for Windows Defender Stig rule V-75237
    Defender1 = @{
        Match  = 'ScheduleDay'
        Select = '(\d[x]\d)\sthrough\s(\d[x]\d)'
    }
}
