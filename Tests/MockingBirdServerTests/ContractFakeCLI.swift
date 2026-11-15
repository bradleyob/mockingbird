import Foundation

/// A POSIX-shell stand-in for the `mockingbird` CLI that follows the parts of contract §4.3
/// the server depends on: argv flags, positional WAV file vs. raw stdin, one line per input
/// (or one per hop with `--continuous`), and exit codes 2/3/4.
///
/// It exists because the real CLI is being rewritten on another branch: until the merge the
/// real binary is the pre-contract one (no exit 3/4, ignores positional files). Each result
/// line also carries `"argv"` so tests can check how parameters reached the CLI. Its "key"
/// is always C; detection accuracy is not the server's concern.
enum ContractFakeCLI {
    static let script = #"""
        rate=44100; window=4096; hop=2048; continuous=0; file=""; argv="$*"
        while [ $# -gt 0 ]; do
          case "$1" in
            --sample-rate) rate="$2"; shift ;;
            --window-size) window="$2"; shift ;;
            --hop-size) hop="$2"; shift ;;
            --alternates|--format) shift ;;
            --zero-pad) ;;
            --continuous) continuous=1 ;;
            --version) echo "mockingbird fake"; exit 0 ;;
            -*) echo "mockingbird: error: unknown option '$1'" >&2; exit 2 ;;
            *) file="$1" ;;
          esac
          shift
        done
        emit() {
          ts=$(awk "BEGIN { printf \"%.3f\", ($1 * $hop + $window) / $rate }")
          printf '{"alternates":[],"argv":"%s","category":"major","confidence":0.9,"key":"C","scaleName":"major","timestamp":%s}\n' "$argv" "$ts"
        }
        insufficient() { echo "mockingbird: error: input ended before one full window" >&2; exit 3; }
        if [ -n "$file" ]; then
          [ -r "$file" ] || { echo "mockingbird: error: cannot read '$file'" >&2; exit 4; }
          [ "$(head -c 4 "$file")" = "RIFF" ] || { echo "mockingbird: error: cannot decode '$file'" >&2; exit 4; }
          samples=$(( ($(wc -c < "$file") - 44) / 2 ))
          [ "$samples" -ge "$window" ] || insufficient
          emit $(( (samples - window) / hop ))
          exit 0
        fi
        if [ "$continuous" = 1 ]; then
          bytes=0; emitted=0
          while :; do
            got=$(dd bs=16384 count=1 2>/dev/null | wc -c)
            [ "$got" -gt 0 ] || break
            bytes=$((bytes + got))
            samples=$((bytes / 4))
            while [ "$samples" -ge "$window" ] && [ $(( (samples - window) / hop + 1 )) -gt "$emitted" ]; do
              emit "$emitted"; emitted=$((emitted + 1))
            done
          done
          [ "$emitted" -gt 0 ] || insufficient
          exit 0
        fi
        samples=$(( $(wc -c | tr -d ' ') / 4 ))
        [ "$samples" -ge "$window" ] || insufficient
        emit $(( (samples - window) / hop ))
        """#
}
