#!/usr/bin/tclsh
#
# Jialin Lu (luxxxlucy@gmail.com)
#
# bperf.tcl: This script processes a Bash script to generate a performance trace output.
# It adds timing information to each command execution and generates a perf.script
#
# Usage: ./bperf.tcl <input_bash_script> [args...]

# Custom logging function that uses logger if available, otherwise falls back to puts
proc log_message {level message} {
    global log_level
    
    set level_order {error warn info debug}
    set level_index [lsearch $level_order $level]
    set log_level_index [lsearch $level_order $log_level]
    
    if {$level_index <= $log_level_index} {
        set formatted_message "\[[string toupper $level]\] $message"
        if {[catch {package require logger}]} {
            puts $formatted_message
        } else {
            ${::log}::$level $message
        }
    }
}

# Set default log level
set log_level "info"

# Try to initialize logger, fall back to custom logging if unavailable
if {[catch {package require logger}]} {
    log_message info "Logger package not available, using fallback logging."
} else {
    set log [logger::init main]
    ${log}::setlevel $log_level
    log_message info "Logger package initialized."
}

proc process_bash_script {input_file output_file args} {
    log_message info "Starting to process Bash script: $input_file"
    
    set in_chan [open $input_file r]
    set out_chan [open $output_file w]
    set temp_log "temp.log"
    set current_path [pwd]

    # Read the first line and check if it's a valid Bash shebang
    set first_line [gets $in_chan]
    if {![string match "#!/bin/bash*" $first_line]} {
        log_message error "Input file does not start with #!/bin/bash"
        close $in_chan
        close $out_chan
        return
    }

    log_message info "Writing modified script to $output_file"
    # Write the shebang and the additional lines at the beginning
    puts $out_chan $first_line
    puts $out_chan {PS4='+ $(date "+%s.%N") ${BASH_SOURCE##*/}:${FUNCNAME[0]:-main}:  '}
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

    log_message info "Executing modified script: $output_file"
    # Run the modified script with arguments, capturing both stdout and stderr
    if {[catch {
        set output [exec bash $output_file {*}$args >&@ stdout]
    } err]} {
        log_message info "Script executed with output (this is expected):"
        log_message info $err
    }

    log_message info "Processing execution log to generate perf.script"
    # Process the temp log and create perf.script
    process_temp_log $temp_log "perf.script" [file tail $input_file] $args
}

proc find_min_time_diff {temp_log} {
    log_message info "Finding minimum time difference in $temp_log"
    
    set in_chan [open $temp_log r]
    set last_time 0
    set min_diff Inf

    while {[gets $in_chan line] != -1} {
        if {[regexp {^\+ (\d+\.\d+)} $line -> time]} {
            if {$last_time != 0} {
                set diff [expr {$time - $last_time}]
                if {$diff < $min_diff && $diff > 0} {
                    set min_diff $diff
                    log_message debug "New minimum time difference found: $min_diff"
                }
            }
            set last_time $time
        }
    }

    close $in_chan
    log_message info "Minimum time difference: $min_diff seconds"
    return $min_diff
}

proc process_temp_log {temp_log perf_script original_script args} {
    log_message info "Processing temp log: $temp_log"
    
    set cycle_unit [find_min_time_diff $temp_log]
    log_message info "Cycle unit set to: $cycle_unit seconds"

    set in_chan [open $temp_log r]
    set out_chan [open $perf_script w]
    set stack {}
    set last_time 0
    set start_time 0
    set script_args [join $args "_"]
    set script_name [string map {" " "_"} $original_script]
    set program_name "${script_name}_${script_args}"

    # Create the base stack entry
    set base_stack "1234 $original_script $args"
    log_message info "Base stack entry: $base_stack"

    while {[gets $in_chan line] != -1} {
        if {[regexp {^\+ (\d+\.\d+) ([^:]+):([^:]+):  (.*)$} $line -> time script func cmd]} {
            set depth [expr {[string length $line] - [string length [string trimleft $line "+"]]}]
            
            if {$start_time == 0} {
                set start_time $time
                log_message debug "Start time set to: $start_time"
            }
            
            if {$last_time != 0} {
                set duration [expr {$time - $last_time}]
                set accumulative_time [expr {$time - $start_time}]
                set cycles [expr {int(ceil($duration / $cycle_unit))}]
                
                log_message debug "Processing entry: time=$time, func=$func, cmd=$cmd"
                log_message debug "Duration: $duration, Accumulative time: $accumulative_time, Cycles: $cycles"
                
                for {set i 0} {$i < $cycles} {incr i} {
                    set cycle_time [expr {$accumulative_time - $duration + ($i + 1) * $cycle_unit}]
                    puts $out_chan "$program_name 1 [format "%.9f" $cycle_time]: 1 cycles:"
                    foreach entry $stack {
                        puts $out_chan "\t$entry"
                    }
                    puts $out_chan "\t$base_stack"
                    puts $out_chan "\n"
                }
            }

            while {[llength $stack] > $depth} {
                set stack [lrange $stack 0 end-1]
            }
            if {$func eq "main"} {
                set stack [list "1234 $cmd (\[$original_script\])"]
            } else {
                set stack [linsert $stack 0 "1234 $cmd (\[$func\])"]
                if {[llength $stack] == 1} {
                    set stack [lappend stack "1234 $func (\[$original_script\])"]
                }
            }
            log_message debug "Updated stack: $stack"
            set last_time $time
        }
    }

    close $in_chan
    close $out_chan
    log_message info "Finished processing. Output written to $perf_script"
}

proc cleanup {files} {
    foreach file $files {
        if {[file exists $file]} {
            file delete $file
            log_message info "Removed temporary file: $file"
        }
    }
}


# Main execution
set clean 1
set args_start 0

if {[lindex $argv 0] eq "--no-clean"} {
    set clean 0
    set args_start 1
}

if {$argc < [expr {$args_start + 1}]} {
    log_message error "Usage: $argv0 \[--no-clean\] <input_bash_script> \[args...\]"
    exit 1
}

set input_file [lindex $argv $args_start]
set output_file "modified_script.sh"
set script_args [lrange $argv [expr {$args_start + 1}] end]

log_message info "Starting script processing"
log_message info "Input file: $input_file"
log_message info "Output file: $output_file"
log_message info "Script arguments: $script_args"
log_message info "Cleanup enabled: [expr {$clean ? "Yes" : "No"}]"

process_bash_script $input_file $output_file {*}$script_args

if {$clean} {
    cleanup [list $output_file "temp.log"]
}

log_message info "Processing complete. Check perf.script for results."