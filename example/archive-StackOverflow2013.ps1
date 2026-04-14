. (Join-Path $PSScriptRoot '..' 'easy-archiving.ps1')

Invoke-EasyArchiving -ConnStr 'Data Source=(local);Initial Catalog=easy-archiving;Connection Timeout=5;
    Encrypt=False;User Id=sa;Password=P1s-Unsee-Me;Application Name=easy-archiving;' `
    -GroupName 'group01' `
    -Verbose
