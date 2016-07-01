properties {
    $base_directory = Resolve-Path .. 
	$publish_directory = "$base_directory\publish-net40"
	$build_directory = "$base_directory\build"
	$src_directory = "$base_directory\src"
	$output_directory = "$base_directory\output"
	$packages_directory = "$src_directory\packages"
	$sln_file = "$src_directory\NEventStore.Persistence.MongoDB.sln"
	$target_config = "Release"
	$framework_version = "v4.5"
	$assemblyInfoFilePath = "$src_directory\VersionAssemblyInfo.cs"
	$version = "0.0.0.0"

	$xunit_path = "$base_directory\bin\xunit.runners.1.9.1\tools\xunit.console.clr4.exe"
	$ilMergeModule.ilMergePath = "$base_directory\bin\ilmerge-bin\ILMerge.exe"
	$nuget_dir = "$src_directory\.nuget"

	if($runPersistenceTests -eq $null) {
		$runPersistenceTests = $false
	}
}

task default -depends Build

task Build -depends Clean, UpdateVersion, Compile, Test

task Clean {
	Clean-Item $publish_directory -ea SilentlyContinue
    Clean-Item $output_directory -ea SilentlyContinue
}

task UpdateVersion {
	$vSplit = $version.Split('.')
	if($vSplit.Length -ne 4)
	{
		throw "Version number is invalid. Must be in the form of 0.0.0.0"
	}
	$major = $vSplit[0]
	$minor = $vSplit[1]
	$assemblyFileVersion = $version
	$assemblyVersion = "$major.$minor.0.0"
	$versionAssemblyInfoFile = "$src_directory/VersionAssemblyInfo.cs"
	"using System.Reflection;" > $versionAssemblyInfoFile
	"" >> $versionAssemblyInfoFile
	"[assembly: AssemblyVersion(""$assemblyVersion"")]" >> $versionAssemblyInfoFile
	"[assembly: AssemblyFileVersion(""$assemblyFileVersion"")]" >> $versionAssemblyInfoFile
	"[assembly: AssemblyInformationalVersion(""$assemblyFileVersion"")]" >> $versionAssemblyInfoFile
}

task Compile {
	EnsureDirectory $output_directory
	exec { msbuild /nologo /verbosity:quiet $sln_file /p:Configuration=$target_config /t:Clean }
	exec { msbuild /nologo /verbosity:quiet $sln_file /p:Configuration=$target_config /p:TargetFrameworkVersion=v4.5 }
}

task Test -precondition { $runPersistenceTests } {
	"Persistence Tests"
	EnsureDirectory $output_directory
	Invoke-XUnit -Path $src_directory -TestSpec '*Persistence.MongoDB.Tests.dll' `
    -SummaryPath $output_directory\persistence_tests.xml `
    -XUnitPath $xunit_path
}

task Package -depends Build {
	move $output_directory $publish_directory
    mkdir $publish_directory\plugins\persistence\mongo | out-null
    copy "$src_directory\NEventStore.Persistence.MongoDB\bin\$target_config\NEventStore.Persistence.MongoDB.???" "$publish_directory\plugins\persistence\mongo"
    copy "$src_directory\NEventStore.Persistence.MongoDB\bin\$target_config\readme.txt" "$publish_directory\plugins\persistence\mongo"
}

task NuGetPack -depends Package {
	gci -r -i *.nuspec "$nuget_dir" |% { .$nuget_dir\nuget.exe pack $_ -basepath $base_directory -o $publish_directory -version $version }
}

function EnsureDirectory {
	param($directory)

	if(!(test-path $directory))
	{
		mkdir $directory
	}
}

# GRD TASKS

function Update-AssemblyInformationalVersion
{
	param
    (
		[string]$version,
		[string]$assemblyInfoFilePath
	)

	$newFileVersion = 'AssemblyInformationalVersion("' + $version + '")';
	$tmpFile = $assemblyInfoFilePath + ".tmp"

	Get-Content $assemblyInfoFilePath |
		%{$_ -replace 'AssemblyInformationalVersion\("[0-9]+(\.([^.]+|\*)){1,4}"\)', $newFileVersion }  | Out-File -Encoding UTF8 $tmpFile

	Move-Item $tmpFile $assemblyInfoFilePath -force
}

task GrdUpdateVersion -depends UpdateVersion {
	#$git_version = (& $base_directory\bin\git\git.exe rev-parse HEAD)
	
	$git_version = (& git.exe rev-parse HEAD)
	
	$version = Get-Version $assemblyInfoFilePath
    "Base Version: $version - Git commit: $git_version"
	$oldVersion = New-Object Version $version
	#$newVersion = New-Object Version ($oldVersion.Major, $oldVersion.Minor, $oldVersion.Build, $git_version)
	#$newVersion = $oldVersion.Major.ToString() + "." + $oldVersion.Minor.ToString() + "." + $oldVersion.Build.ToString() + "." + $build_number.ToString() + "." + $git_version
	$newVersion = "$oldVersion.$git_version"
    "New Version: $newVersion"
	Update-AssemblyInformationalVersion $newVersion $assemblyInfoFilePath
}

task GrdBuild -depends Clean, UpdateVersion, GrdUpdateVersion, Compile, Test

task GrdPackage -depends GrdBuild {
	move $output_directory $publish_directory
    mkdir $publish_directory\plugins\persistence\mongo | out-null
    copy "$src_directory\NEventStore.Persistence.MongoDB\bin\$target_config\NEventStore.Persistence.MongoDB.???" "$publish_directory\plugins\persistence\mongo"
    copy "$src_directory\NEventStore.Persistence.MongoDB\bin\$target_config\readme.txt" "$publish_directory\plugins\persistence\mongo"
}

# END GRD TASKS
