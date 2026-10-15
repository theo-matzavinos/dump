# Helpers for the "Docker behind the scenes" lab: PowerShell on Windows.
#
# Load it into your current PowerShell session by dot-sourcing it
# (don't run it as a separate program):
#
#   . .\lab-helpers.ps1
#
# Loading it:
#   - creates a new lab directory with a random name under your temporary
#     directory and moves your session into it;
#   - checks that Docker answers, that the web port is free, and that nothing
#     in Docker already uses the lab's random name;
#   - sets $lab, $lab_dir, $lab_share and $lab_user for the article's commands,
#     and sets $env:COMPOSE_PROJECT_NAME and $env:WEB_PORT for Docker Compose.
#
# The article's docker commands add --label "docker-lab=$lab" to the containers
# and images they create, and compose.yaml adds the same label to its images.
#
# When you're done, run Remove-DockerLab. It first lists and checks everything
# it will remove: the experiment containers and the exact image tags the
# article creates (each must carry the lab's label), plus the containers,
# network and volume of the lab's Compose project (each must have the expected
# name). If a check fails, or Docker reports an error while checking, it stops
# before deleting anything. Then it removes that list and the lab directory. If
# Docker fails partway through, what's already removed can't be restored; fix
# the error and run Remove-DockerLab again.
#
# Cleanup leaves untagged images alone. Rebuilding a tag leaves the older image
# without a name, but a label alone can't show whether the lab built it or
# another image was built FROM a lab image and inherited the label.
#
# Works in Windows PowerShell 5.1 and PowerShell 7.

# Runs docker and throws if it fails. Windows PowerShell doesn't stop on a
# failing program by itself, so every Docker call in this file goes through here.
function Invoke-LabDocker {
    # 'Continue' keeps Docker's error text visible instead of turning it into
    # a PowerShell error before the exit code is checked.
    $ErrorActionPreference = 'Continue'
    $global:LASTEXITCODE = $null
    $output = & docker @args
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "lab: 'docker $args' failed with exit code $exitCode."
    }
    $output
}

# Lists the ID of every resource of one kind (container, network, volume)
# that Docker Compose created for this lab's project.
function Get-LabProjectId {
    param([string] $Kind)

    $filter = "label=com.docker.compose.project=$lab"
    if ($Kind -ceq 'container') {
        Invoke-LabDocker container ls --all --quiet --filter $filter
        return
    }
    Invoke-LabDocker $Kind ls --quiet --filter $filter
}

# Returns the name of one resource that a list command just returned.
function Get-LabResourceName {
    param([string] $Kind, [string] $Id)

    Invoke-LabDocker $Kind inspect --format '{{.Name}}' $Id
}

function Initialize-DockerLab {
    $ErrorActionPreference = 'Stop'

    if ($lab) {
        throw "lab: this session already has a lab ($lab). Run Remove-DockerLab or open a new window."
    }

    $null = Invoke-LabDocker version
    $null = Invoke-LabDocker compose version

    $port = 8080
    if ($env:WEB_PORT) {
        $port = [int] $env:WEB_PORT
    }
    if ($port -lt 1024 -or $port -gt 65535) {
        throw 'lab: choose a WEB_PORT between 1024 and 65535.'
    }
    # Starting a listener fails if another program already listens on the port.
    $listener = New-Object -TypeName System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), $port
    try {
        $listener.ExclusiveAddressUse = $true
        $listener.Start()
    } catch {
        throw "lab: port $port is in use. Run `$env:WEB_PORT = '8081' (or another free port) and load this file again."
    } finally {
        $listener.Stop()
    }

    $name = 'dockerscenes-' + [Guid]::NewGuid().ToString('N').Substring(0, 16)

    # Docker's name filters match parts of names, so this also catches
    # "$name-web-1", "${name}_dbdata" and the like.
    $found = @()
    $found += @(Invoke-LabDocker container ls --all --quiet --filter "name=$name")
    $found += @(Invoke-LabDocker container ls --all --quiet --filter "label=com.docker.compose.project=$name")
    $found += @(Invoke-LabDocker network ls --quiet --filter "name=$name")
    $found += @(Invoke-LabDocker volume ls --quiet --filter "name=$name")
    $found += @(Invoke-LabDocker image ls --quiet --filter "reference=$name-*")
    if (@($found | Where-Object { $_ }).Count -ne 0) {
        throw "lab: Docker already has resources named $name. Load this file again to pick a new name."
    }

    $dir = Join-Path ([System.IO.Path]::GetTempPath()) $name
    $null = New-Item -ItemType Directory -Path $dir
    $null = New-Item -ItemType Directory -Path (Join-Path $dir 'layers'), (Join-Path $dir 'api'), (Join-Path $dir 'share')
    $utf8 = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText((Join-Path $dir '.lab-owner'), "$name`n", $utf8)
    Set-Location -LiteralPath $dir

    # Containers that write into the lab directory run as this user. Docker
    # Desktop on Windows maps file ownership itself, so root (0:0) is fine
    # there; on Linux and macOS, use your own IDs as the bash helpers do.
    $user = '0:0'
    if ($IsLinux -or $IsMacOS) {
        $user = "$(& id -u):$(& id -g)"
    }

    $global:lab = $name
    $global:lab_dir = $dir
    $global:lab_share = Join-Path $dir 'share'
    $global:lab_user = $user
    $env:COMPOSE_PROJECT_NAME = $name
    $env:WEB_PORT = "$port"

    Write-Host "Lab name:      $lab"
    Write-Host "Lab directory: $lab_dir"
    Write-Host "Web port:      $env:WEB_PORT"
}

# Confirms that the lab directory is the one Initialize-DockerLab created.
function Confirm-LabDirectory {
    $ErrorActionPreference = 'Stop'

    if (-not $lab -or -not $lab_dir) {
        throw 'lab: this session has no lab. Run cleanup from the window where you loaded the helpers.'
    }
    if ($lab -cnotmatch '^dockerscenes-[0-9a-f]{16}$') {
        throw "lab: the lab name changed to '$lab'. Nothing was removed."
    }
    $ownerPath = Join-Path $lab_dir '.lab-owner'
    if ((Split-Path -Leaf $lab_dir) -cne $lab -or -not (Test-Path -LiteralPath $ownerPath -PathType Leaf)) {
        throw "lab: the lab directory '$lab_dir' doesn't belong to $lab. Nothing was removed."
    }
    $owner = (Get-Content -LiteralPath $ownerPath -Raw).Trim()
    if ($owner -cne $lab) {
        throw "lab: the lab directory's owner file changed. Nothing was removed."
    }
}

# Returns the value of the docker-lab label on one container or image.
function Get-LabLabel {
    param([string] $Kind, [string] $Id)

    # Windows PowerShell 5.1 drops double quotes inside the arguments it passes
    # to programs, so a template such as {{index .Config.Labels "docker-lab"}}
    # would arrive broken. Ask for all labels as JSON and read the key here.
    $json = @(Invoke-LabDocker $Kind inspect --format '{{json .Config.Labels}}' $Id) -join "`n"
    $labels = ConvertFrom-Json -InputObject $json
    if ($null -eq $labels) {
        return ''
    }
    $labels.'docker-lab'
}

# Runs one removal. If it fails, earlier removals can't be undone, so say so.
function Invoke-LabRemoval {
    try {
        $null = Invoke-LabDocker @args
    } catch {
        throw "lab: cleanup stopped partway. What it already removed stays removed; fix the error above and run Remove-DockerLab again. ($($_.Exception.Message))"
    }
}

function Remove-DockerLab {
    $ErrorActionPreference = 'Stop'

    Confirm-LabDirectory

    # First list and check everything to remove. Nothing is deleted until every
    # check has passed, and any Docker error during the checks stops cleanup.
    $containers = @()
    $networks = @()
    $volumes = @()
    $images = @()

    # Compose labels everything it creates with the project name, which is the
    # lab's random name. Every such resource must have a name the lab expects.
    foreach ($kind in @('container', 'network', 'volume')) {
        foreach ($id in @(Get-LabProjectId $kind)) {
            if (-not $id) {
                continue
            }
            $resourceName = Get-LabResourceName $kind $id
            $key = "${kind}:$resourceName"
            if (@("container:/$lab-web-1", "container:/$lab-api-1", "container:/$lab-db-1") -ccontains $key) {
                $containers += $id
            } elseif ($key -ceq "network:${lab}_default") {
                $networks += $id
            } elseif ($key -ceq "volume:${lab}_dbdata") {
                $volumes += $id
            } else {
                throw "lab: unexpected $kind '$resourceName' in project $lab. Inspect it yourself; nothing was removed."
            }
        }
    }

    # The article's experiment containers carry the lab's label.
    $names = @(Invoke-LabDocker container ls --all --format '{{.Names}}')
    foreach ($name in @('exit', 'a', 'b')) {
        if ($names -ccontains "$lab-$name") {
            if ((Get-LabLabel container "$lab-$name") -cne $lab) {
                throw "lab: container $lab-$name doesn't carry this lab's label, so nothing was removed. If you created it in this lab, check it with 'docker container inspect $lab-$name', remove it with 'docker container rm --force $lab-$name', and run Remove-DockerLab again."
            }
            $containers += "$lab-$name"
        }
    }

    # Only the exact tags the article creates, and only if they carry the label.
    foreach ($tag in @("$lab-layers:latest", "$lab-web:1", "$lab-web:2", "$lab-web:3", "$lab-web:latest", "$lab-api:latest")) {
        $found = @(Invoke-LabDocker image ls --quiet --filter "reference=$tag") | Where-Object { $_ }
        if ($found) {
            if ((Get-LabLabel image $tag) -cne $lab) {
                throw "lab: image $tag doesn't carry this lab's label, so nothing was removed. If you created it in this lab, check it with 'docker image inspect $tag', remove it with 'docker image rm $tag', and run Remove-DockerLab again."
            }
            $images += $tag
        }
    }

    foreach ($id in $containers) {
        Invoke-LabRemoval container rm --force $id
    }
    foreach ($id in $networks) {
        Invoke-LabRemoval network rm $id
    }
    foreach ($id in $volumes) {
        Invoke-LabRemoval volume rm $id
    }
    # Removing by tag, without --force, leaves any other tag on the same image alone.
    foreach ($tag in $images) {
        Invoke-LabRemoval image rm $tag
    }

    Set-Location -LiteralPath (Split-Path -Parent $lab_dir)
    Remove-Item -LiteralPath $lab_dir -Recurse -Force

    Write-Host "Removed lab ${lab}: its containers, network, volume, images and directory."
    Write-Host 'The base images (node, nginx, postgres) and Docker''s build cache stay.'

    Remove-Variable -Name lab, lab_dir, lab_share, lab_user -Scope Global
    foreach ($variable in @('COMPOSE_PROJECT_NAME', 'WEB_PORT', 'SERVICE_MESSAGE', 'BROWSER_GREETING', 'BUILD_LABEL')) {
        Remove-Item -Path "Env:$variable" -ErrorAction SilentlyContinue
    }
}

Initialize-DockerLab
