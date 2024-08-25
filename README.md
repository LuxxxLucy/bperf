# bperf

Profile Bash scripts and output a perf.script file.  Usage:
```
./bperf.tcl your_script.sh [arg1 arg2 ...]
```

append `--no-clean` if you do not want to clean up the temp files 
```
./bperf.tcl --no-clean your_script.sh ...
```

Requirements:
- Bash (well, you want to run bash so you must have bash)
- Tcl (believe it or not, it's probably installed on your system if you are using UNIX)

Limitations:
- macOS users: The default `date` on macOS doesn't support printing-out nanoseconds. Install `gdate` for full functionality.
- Currently does not support recursive scripts, so only the outest main script. Nested script calls are not accurately profiled. **Will probably be addressed in future updates.**