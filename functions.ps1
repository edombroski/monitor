Function Write-Status
{
    Param
    (
        [string]$Status,
        [switch]$Error
    )

    If($Error) { $Color = "Red" }
    Else { $Color = "Blue" }
    Write-Host -ForegroundColor "White" -NoNewLine "["
    Write-Host -ForegroundColor $Color -NoNewLine $Status
    Write-Host -ForegroundColor "White" "]"
}
