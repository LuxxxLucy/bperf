#!/usr/bin/tclsh

proc process_bash_script {input_file output_file} {
    set in_chan [open $input_file r]
    set out_chan [open $output_file w]
    set temp_log "temp.log"
    set current_path [pwd]

    # Read the first line and check if it's a valid Bash shebang
    set first_line [gets $in_chan]
    if {![string match "#!/bin/bash*" $first_line]} {
        puts "Error: The input file does not start with #!/bin/bash"
        close $in_chan
        close $out_chan
        return
    }

    # Write the shebang and the additional lines at the beginning
    puts $out_chan $first_line
    puts $out_chan "PS4='+ \$(date \"+%s.%N\") \${BASH_SOURCE\[0\]}:\${FUNCNAME\[0\]}>>>\\011 '"
    puts $out_chan "exec 3>&2 2>${current_path}/${temp_log}"
    puts $out_chan "set -x"

    # Process the rest of the file
    while {[gets $in_chan line] != -1} {
        if {![string match "#*" $line]} {
            puts $out_chan $line
        }
    }

    # Add lines at the end of the script
    puts $out_chan "set +x"
    puts $out_chan "exec 2>&3 3>&-"

    close $in_chan
    close $out_chan

    # Make the modified script executable
    exec chmod +x $output_file

    # Run the modified script, capturing both stdout and stderr
    if {[catch {
        set output [exec bash $output_file >&@ stdout]
    } err]} {
        puts "Note: Script executed with output (this is expected):"
        puts $err
    }

    # Process the temp log and create perf.script
    process_temp_log $temp_log "perf.script"
}

proc process_temp_log {temp_log perf_script} {
    set in_chan [open $temp_log r]
    set out_chan [open $perf_script w]
    set stack {}
    set last_time 0

    while {[gets $in_chan line] != -1} {
        if {[regexp {^\+ (\d+\.\d+)\s+(.*)$} $line -> time cmd]} {
            set depth [expr {[string length $line] - [string length [string trimleft $line "+"]]}]
            
            if {$last_time != 0} {
                set duration [expr {$time - $last_time}]
                puts $out_chan "egg-run-program 1 [format "%.6f" $duration]: 1 cycles:"
                for {set i 0} {$i < [llength $stack]} {incr i} {
                    puts $out_chan "\t1234 [lindex $stack $i] (\[egg-func-lib\])"
                }
                puts $out_chan "\n"
            }

            while {[llength $stack] >= $depth} {
                set stack [lrange $stack 0 end-1]
            }
            lappend stack $cmd
            set last_time $time
        }
    }

    close $in_chan
    close $out_chan
}

# Main execution
if {$argc != 1} {
    puts "Usage: $argv0 <input_bash_script>"
    exit 1
}

set input_file [lindex $argv 0]
set output_file "modified_script.sh"

process_bash_script $input_file $output_file
puts "Processing complete. Check perf.script for results."
