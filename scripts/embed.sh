#!/usr/bin/env bash

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
  placeholder="EMBED_PLACEHOLDER"

  # Check if the input file exists
  if [ ! -f "$input_file" ]; then
      echo "Input file not found!"
      exit 1
  fi

  # Read the contents of the input file
  content=$(<"$input_file")

  # Escape only double quotation marks that aren't already escaped
  escaped_content=$(
    echo "$content" |
    awk '{printf "%s\\n",$0}' |
    sed 's/\([^\\]\)"/\1\\"/g; s/^"/\\"/g; s/\\""/\\"\\"/g; s/[&/\]/\\&/g')

  sed -i '' "s/${placeholder}/${escaped_content}/" "$output_file"

  # echo "Placeholder text replaced successfully in $output_file"

done
