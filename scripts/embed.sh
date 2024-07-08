#!/usr/bin/env bash

# Form of placeholder
placeholder="__CONJURE_EMBED__"

# Check if the directory path is provided as argument
if [ $# -ne 1 ]; then
    echo "Usage: $0 <directory_path>"
    exit 1
fi

# Directory path provided as argument
directory="$1"

# File extension to exclude
file_extension=".fnl"

# Array to store file paths
declare -a file_paths

# Find all files not matching the extension recursively
while IFS= read -r -d '' file; do
    if [[ ! "$file" =~ $file_extension$ ]]; then
        file_paths+=("$file")
    fi
done < <(find "$directory" -type f -print0)

# Print all collected file paths
for path in "${file_paths[@]}"; do
  input_file="$path"
  input_file_no_ext=${path%.*}
  output_file="lua${input_file_no_ext:3}.lua"

  # Check if the input file exists
  if [ ! -f "$input_file" ]; then
      echo "Input file not found!"
      exit 1
  fi

  # Create a temporary file
  temp_file=$(mktemp)

  # Process the input file: escape special characters, newlines and double quotes
  sed -e 's/&/\\\&/g' \
    -e 's/"/\\"/g' \
    -e 's/$/\\n/' \
    "$input_file" | tr -d '\n' > "$temp_file"

  # Process the template file and generate the output
  output=$(awk -v placeholder="$placeholder" -v temp_file="$temp_file" '
      BEGIN {
          getline escaped_content < temp_file
          close(temp_file)
      }
      {
          gsub(placeholder, escaped_content)
          print
      }
      ' "$output_file")

  echo "$output" > $output_file

  # Remove the temporary file
  rm "$temp_file"
done
