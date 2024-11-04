#!/bin/bash

# How to use valint.
# Valint can output pure sarif,statement or attestation.
# valint verify [target] [FLAGS] -o sarif
# valint verify [target] [FLAGS] -o statement (default)
# valint verify [target] [FLAGS] -o attest
# Provide the evidence output file in cache or `--output-file` flag.
# Provde it to this script -F flag
# For example,
# valint verify --bom busybox:latest -o attest --output-file busyxbox.sarif.statement.json
# valint-gitlab-converter.sh -F busybox.sarif.statement.json -O busybox.gitlab.json
#!/bin/bash

OUTPUT_FILE=output.gitlab.json
BIN=./sarif-converter  # Default binary location
INSTALL=false           # Flag to control installation if sarif-converter is missing
FILE_TYPE=""            # Optional flag for file type (sarif, statement, attest)

usage() {
  echo "Usage: $0 [-F <file-path>] [-B <binary-path>] [-O <output-file>] [-T <type>] [-x] [-i] [-h]"
  echo
  echo "Options:"
  echo "  -F <file-path>     Specify the file to process."
  echo "  -B <binary-path>   Specify the path to the sarif-converter binary (default: ./sarif-converter)."
  echo "  -O <output-file>   Specify the output file (default: output.gitlab.json)."
  echo "  -T <type>          Specify the file type (sarif, statement, or attest) to override file extension detection."
  echo "  -x                 Enable debug mode (set -x)."
  echo "  -i                 Install sarif-converter if not found."
  echo "  -h, --help         Show this help message and exit."
  echo
  echo "This script processes different types of JSON files, converting them with the sarif-converter binary."
  echo "Examples:"
  echo "  $0 -F example.sig.json"
  echo "  $0 -x -F example.sarif.json -T sarif"
}

# Check dependencies and binary, with optional installation
check_dependencies() {
  for tool in jq base64; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "Error: Required tool '$tool' is not installed." >&2
      echo "Please install '$tool' and try again."
      exit 1
    fi
  done

  if [ ! -x "$BIN" ]; then
    if $INSTALL; then
      echo "sarif-converter not found. Installing..."
      wget -O "$BIN" "https://gitlab.com/ignis-build/sarif-converter/-/releases/permalink/latest/downloads/bin/sarif-converter-linux-amd64"
      chmod +x "$BIN"
      sync  # Ensure all writes are flushed to disk
      sleep 1  # Brief pause to avoid "Text file busy" error
      echo "sarif-converter installed successfully."
    else
      echo "Error: sarif-converter binary not found or not executable at '$BIN'." >&2
      echo "Please specify a valid path to the binary using the -B option, or use -i to install it."
      exit 1
    fi
  fi
}

# Parse command-line arguments
parse_args() {
  while getopts "F:B:O:T:xi:h" arg; do
    case "$arg" in
      F)
        FILE_NAME=$OPTARG
        ;;
      B)
        BIN=$OPTARG
        ;;
      O)
        OUTPUT_FILE=$OPTARG
        ;;
      T)
        FILE_TYPE=$OPTARG
        ;;
      x)
        echo "Debug mode enabled."
        set -x
        ;;
      i)
        INSTALL=true
        ;;
      h)
        usage
        exit 0
        ;;
      *)
        echo "Invalid option: -$OPTARG" >&2
        usage
        exit 1
        ;;
    esac
  done
  shift $((OPTIND - 1))

  if [ -z "$FILE_NAME" ]; then
    echo "Error: File name is required. Use -F <file-path>" >&2
    usage
    exit 1
  fi
}

# Process the input file based on its extension or specified type
process_file() {
  local TEMP_FILE
  TEMP_FILE=$(mktemp)

  case "$FILE_TYPE" in
    attest)
      echo "Processing as Attestation file: $FILE_NAME"
      if ! cat "$FILE_NAME" | jq -r '.payload' | base64 -d | jq -r '.payload' | base64 --decode | jq '.predicate.content' > "$TEMP_FILE"; then
        echo "Error: Failed to decode or process attestation file '$FILE_NAME'." >&2
        rm -f "$TEMP_FILE"
        exit 1
      fi
      ;;
    statement)
      echo "Processing as Statement file: $FILE_NAME"
      if ! jq .predicate.content "$FILE_NAME" > "$TEMP_FILE"; then
        echo "Error: Failed to process statement file '$FILE_NAME'." >&2
        rm -f "$TEMP_FILE"
        exit 1
      fi
      ;;
    sarif)
      echo "Processing as Sarif file: $FILE_NAME"
      TEMP_FILE="$FILE_NAME"  # Directly use the .sarif file
      ;;
    "")
      # Determine file type based on extension if FILE_TYPE is not specified
      case "$FILE_NAME" in
        *.sig.json)
          echo "Processing as Signed Statement file: $FILE_NAME"
          if ! cat "$FILE_NAME" | jq -r '.payload' | base64 -d | jq -r '.payload' | base64 --decode | jq '.predicate.content' > "$TEMP_FILE"; then
            echo "Error: Failed to decode or process signed statement file '$FILE_NAME'." >&2
            rm -f "$TEMP_FILE"
            exit 1
          fi
          ;;
        *.statement.json | *.sarif.json)
          echo "Processing Statement file: $FILE_NAME"
          if ! jq .predicate.content "$FILE_NAME" > "$TEMP_FILE"; then
            echo "Error: Failed to process statement file '$FILE_NAME'." >&2
            rm -f "$TEMP_FILE"
            exit 1
          fi
          ;;
        *.sarif)
          echo "Processing as Sarif file: $FILE_NAME"
          TEMP_FILE="$FILE_NAME"  # Directly use the .sarif file
          ;;
        *)
          echo "Error: Unsupported file type. Use a file with .sig.json, .statement.json, or .sarif.json suffix, or specify -T <type>." >&2
          rm -f "$TEMP_FILE"
          exit 1
          ;;
      esac
      ;;
    *)
      echo "Error: Invalid file type specified. Use 'sarif', 'statement', or 'attest'." >&2
      exit 1
      ;;
  esac

  # Run sarif-converter and handle any errors
  if ! "$BIN" "$TEMP_FILE" "$OUTPUT_FILE" -t sast; then
    echo "Error: sarif-converter failed to process the file." >&2
    rm -f "$TEMP_FILE"
    exit 1
  fi

  # Clean up if a temporary file was used
  [ "$TEMP_FILE" != "$FILE_NAME" ] && rm -f "$TEMP_FILE"
}

# Main execution
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

parse_args "$@"
check_dependencies
process_file
