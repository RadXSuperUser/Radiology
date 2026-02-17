$Pattern = Read-Host "Filename pattern"
Get-ChildItem -Recurse -Include *$Pattern* -File | Select-Object -ExpandProperty FullName
