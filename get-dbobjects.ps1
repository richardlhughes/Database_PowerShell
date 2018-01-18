#Get the database names
[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null
$ServerName='telusdwqa\mssql2016'# the server it is on
$s = New-Object ('Microsoft.SqlServer.Management.Smo.Server') $ServerName
$dbs=$s.Databases | Where {(!($_.name -Like "*temp*" )) -and ($_.id -le 4)}
$exclude=$s.Databases | Where {$_.name -Like "*temp*"}
$countExclude=$exclude.count
#$dbs | Get-Member -MemberType Property | Where {$_.id -eq 9}
$dbname = $dbs.name
## Start script from https://www.mssqltips.com/sqlservertip/1759/retrieve-a-list-of-sql-server-databases-and-their-properties-using-powershell/
$count = $dbname.count
echo "There are $($count) databases on $($ServerName) to be extracted"
echo "$($countExclude) will be skipped"
echo "Skipping the following databases $($exclude.Name)"
echo "Starting the extract..."
ForEach ($Database in $dbname){
echo "The current database is $($Database)"
#Start-Job -Name 'backup_$($Database)' -ScriptBlock{
#$Database=$dbname[0].Name # the name of the database you want to script as objects
$DirectoryToSaveTo="C:\src\telusdwqa\" # the directory where you want to store them
# Load SMO assembly, and if we're running SQL 2008 DLLs load the SMOExtended and SQLWMIManagement libraries
$v = [System.Reflection.Assembly]::LoadWithPartialName( 'Microsoft.SqlServer.SMO')
if ((($v.FullName.Split(','))[1].Split('='))[1].Split('.')[0] -ne '9') {
    [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMOExtended') | out-null
}
[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SmoEnum') | out-null
set-psdebug -strict # catch a few extra bugs
$ErrorActionPreference = "stop"
$My='Microsoft.SqlServer.Management.Smo'
$srv = new-object ("$My.Server") $ServerName # attach to the server
if ($srv.ServerType-eq $null) # if it managed to find a server
   {
   Write-Error "Sorry, but I couldn't find Server '$ServerName' "
   return
} 
$scripter = new-object ("$My.Scripter") $srv # create the scripter
$scripter.Options.ToFileOnly = $true 
# we now get all the object types except extended stored procedures
# first we get the bitmap of all the object types we want 
$all =[long] [Microsoft.SqlServer.Management.Smo.DatabaseObjectTypes]::all `
    -bxor [Microsoft.SqlServer.Management.Smo.DatabaseObjectTypes]::ExtendedStoredProcedure
# and we store them in a datatable
$d = new-object System.Data.Datatable
# get everything except the servicebroker object, the information schema and system views
$d=$srv.databases[$Database].EnumObjects([long]0x1FFFFFFF -band $all) | `
    Where-Object {$_.Schema -ne 'sys'-and $_.Schema -ne "information_schema" -and $_.DatabaseObjectTypes -ne 'ServiceBroker' -and $_.DatabaseObjectTypes -ne 'Certificate' -and $_.DatabaseObjectTypes -ne 'SymmetricKey' -and $_.DatabaseObjectTypes -ne 'AsymmetricKey'}
# and write out each scriptable object as a file in the directory you specify
$d| FOREACH-OBJECT { # for every object we have in the datatable.
   $SavePath="$($DirectoryToSaveTo)\$($Database)\$($_.DatabaseObjectTypes)"
   # create the directory if necessary (SMO doesn't).
   if (!( Test-Path -path $SavePath )) # create it if not existing
        {Try { New-Item $SavePath -type directory | out-null } 
        Catch [system.exception]{
            Write-Error "error while creating '$SavePath' $_"
            return
         } 
    }
    # tell the scripter object where to write it
    if (!( $_.schema)){
    $scripter.Options.Filename = "$SavePath\$($_.name -replace '[\\\/\:\.]','-').sql";
    }
    else{
    $scripter.Options.Filename = "$SavePath\$($_.schema).$($_.name -replace '[\\\/\:\.]','-').sql";
    }
    # Create a single element URN array
    $UrnCollection = new-object ('Microsoft.SqlServer.Management.Smo.urnCollection')
    $URNCollection.add($_.urn)
    # and write out the object to the specified file
    $scripter.script($URNCollection)
	} 
}#}
echo "Oh wise one, All is written out!"