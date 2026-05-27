param(
    [string]$HostAlias = "A6000_2",
    [int]$LocalPort = 8188,
    [int]$RemotePort = 8188
)

ssh -N -L "${LocalPort}:127.0.0.1:${RemotePort}" $HostAlias
