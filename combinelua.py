import os
import sys
import re


def resolve_path(base_path, include_path):
    """Resolve relative paths based on the base file's location."""
    return os.path.normpath(os.path.join(os.path.dirname(base_path), include_path))


def process_file(input_path, processed_files=None):
    if processed_files is None:
        processed_files = set()

    if input_path in processed_files:
        return ""

    processed_files.add(input_path)
    output = []

    include_pattern = re.compile(r'^\s*#include\s+["\']?([^"\'\s]+)["\']?')

    with open(input_path, errors='ignore') as file:
        for line_number, line in enumerate(file, 1):
            if line.lstrip().startswith('--'):
                output.append(line)
                continue

            match = include_pattern.search(line)
            if match:
                include_path = match.group(1)
                resolved_path = resolve_path(input_path, include_path)
                if os.path.exists(resolved_path):
                    try:
                        included_content = process_file(resolved_path, processed_files)
                        if not included_content.endswith('\n'):
                            included_content += '\n'
                        output.append(included_content)
                    except Exception as e:
                        print(f"Error processing file {resolved_path} at line {line_number} in {input_path}: {e}")
                        sys.exit(1)
                else:
                    print(f"Warning: Included file not found: {resolved_path} at line {line_number} in {input_path}. Skipping...")
            else:
                output.append(line)

    return ''.join(output)


def main():
    if len(sys.argv) != 3:
        print("Usage: python combinelua.py <input_file> <output_file>")
        sys.exit(1)

    input_filename = sys.argv[1]
    output_filename = sys.argv[2]

    try:
        combined_content = process_file(input_filename)
        with open(output_filename, 'w') as output_file:
            output_file.write(combined_content)
        print(f"Successfully combined into {output_filename}")
    except FileNotFoundError as e:
        print(e)
        sys.exit(1)


if __name__ == "__main__":
    main()
