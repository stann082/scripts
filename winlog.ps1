param (
    [Alias("n")]
    [string]$name = "application",
    [Alias("l")]
    [int]$length = 10,
    [Alias("s")]
    [string]$source,
    [Alias("b")]
    [datetime]$before,
    [Alias("a")]
    [datetime]$after,
    [Alias("t")]
    [string]$type,
    [switch]$wrap,
    [switch]$help
)

function Show-Usage {
    @"
    Usage: winlog [-t log_type] [-l length] [-w wrap_log_entries]
    Example: winlog -n system -l 20 -w
    Options:
        -n, --name                        : specify log name (e.g. system, application, security, setup [default: application])
        -l, --length                      : specify the number of log entries to display (e.g. 20 [default: 10])
        -s, --source                      : specify the source of the log
        -b, --before                      : specify the before date (e.g. 2024-09-18 15:21)
        -a, --after                       : specify the after date (e.g. 2024-09-18 15:21)
        -t, --type                        : specify the type (e.g. error, information, warning)
        -w, --wrap                        : wrap log entries for better readability
"@
}

if ($help) {
    Show-Usage
    exit
}

$command = @{
    LogName = $name
    Newest  = $length
}

if ($source) {
    $command.Source = $source
}

if ($type) {
    $command.EntryType = $type
}

if ($before) {
    $command.Before = $before
}

if ($after) {
    $command.After = $after
}

$logs = Get-EventLog @command

if ($wrap) {
    $logs | Format-Table -AutoSize -Wrap
} else {
    $logs
}