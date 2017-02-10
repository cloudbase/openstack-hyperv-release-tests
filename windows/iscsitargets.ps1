if (-not ("PersistentTarget" -as [type])) {
    Add-Type -Language CSharp @"
public class PersistentTarget {
    public string name;
    public string portalAddr;
    public string portalPort;
    public string initiator;
}
"@;
}

function parse_iscsicli_output($output, $field) {
    $values = @()
    $output | select-string $field | `
        % {$_ -match "$field *: (.*)";
           $values += $matches[1]} | Out-Null
    return $values
}

function get_iscsi_persistent_targets() {
    $out = iscsicli listpersistenttargets
    $out | select-string "total of" | `
        % { $_ -match 'Total of ([0-9]*) .*'} | Out-Null

    $count = $matches[1]
    $targets = @()

    if ($count -ne "0") {
        $targets = (1..$count) | % { new-object PersistentTarget}
        parse_iscsicli_output $out "Target Name" | `
            % {$i = 0} {$targets[$i].name = $_; $i++}
        parse_iscsicli_output $out "Initiator Name" | `
            % {$i = 0} {$targets[$i].initiator = $_; $i++}
        parse_iscsicli_output $out "Address and Socket" | `
            % {$i = 0} `
              {$targets[$i].portalAddr, `
               $targets[$i].portalPort = $_.split(" ");
               $i++}
    }
    return $targets
}

function log_targets($log_prefix) {
    $targets = get-iscsitarget
    $portals = get-iscsitargetportal
    $targets_count = $targets.Count
    $portals_count = $portals.Count

    log_message "$log_prefix $env:computername has $targets_count iSCSI targets."
    iscsicli listpersistenttargets
    iscsicli listtargets
    log_message "$log_prefix $env:computername has $portals_count iSCSI portals."
    iscsicli listtargetportals
}

function log_message($message){
    Write-Host "[$(Get-Date)] $message"
}

function cleanup_iscsi_targets() {
    $ErrorActionPreference = "Continue"
    log_targets "[PRE_CLEAN]"
    log_message "Started cleaning iSCSI targets and portals"

    log_message "Forcing refreshing iSCSI targets. This may take a while..."
    iscsicli listtargets 1
    log_message "Refreshed iSCSI targets."

    $targets = get-iscsitarget
    $persistent_targets = get_iscsi_persistent_targets

    foreach ($target in $targets) {
        $target_name = $target.NodeAddress

        log_message "Fetching iSCSI sessions"
        $sessions = get-iscsisession -iscsitarget $target -ErrorAction Ignore
        foreach ($session in $sessions) {
            $sid = $session.SessionIdentifier
            log_message "Removing iSCSI session $sid ($target_name)"
            iscsicli logouttarget $sid
        }
        log_message "Removing target $target_name."
        # This works only for statically added targets.
        iscsicli RemoveTarget $target_name
    }

    foreach ($target in $persistent_targets) {
        $target_name = $target.name
        log_message "Removing persistent target: $target_name"
        iscsicli removepersistenttarget `
            $target.initiator $target.name * `
            $target.portalAddr $target.portalPort
    }

    $portals = get-iscsitargetportal
    foreach ($portal in $portals) {
        log_message "Removing portal $portal"
        remove-iscsitargetportal -TargetPortalAddress $portal.TargetPortalAddress -confirm:$false
    }

    # Restarting MSiSCSI service 
    restart-service msiscsi; 

    log_message "Finished cleaning iSCSI targets and portals"
    log_targets "[POST_CLEAN]"
}

cleanup_iscsi_targets
