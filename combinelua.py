import os
import sys
import re

def resolve_path(base_path, include_path):
    """Resolve relative paths based on the base file's location."""
    return os.path.normpath(os.path.join(os.path.dirname(base_path), include_path))

def process_line_for_stripping(line, in_multiline_comment):
    """
    Strips comments from a single line of Lua code, aware of strings.
    It trims the comment entirely and ends the line with a newline,
    preserving the line count but not the original character positions.

    Returns a tuple: (processed_line, new_in_multiline_comment_state)
    """
    non_comment_part = ""
    i = 0
    n = len(line)
    in_string_char = None  # Will hold ' or " if inside a string

    while i < n:
        if in_multiline_comment:
            end_pos = line.find("]]", i)
            if end_pos != -1:
                # End of multiline comment found. Skip past it.
                i = end_pos + 2
                in_multiline_comment = False
            else:
                # The rest of the line is part of a multiline comment, so we output nothing for this line.
                i = n
                
        elif in_string_char:
            non_comment_part += line[i]
            if line[i] == '\\' and i + 1 < n:  # Handle escape character
                non_comment_part += line[i+1]
                i += 2
            elif line[i] == in_string_char:  # End of string
                in_string_char = None
                i += 1
            else:
                i += 1
        else:
            if line[i:i+4] == '--[[':
                in_multiline_comment = True
                i += 4
            elif line[i:i+2] == '--':
                # Single line comment. The rest of the line is ignored.
                i = n # Break the loop
            elif line[i] in ('"', "'"):
                in_string_char = line[i]
                non_comment_part += line[i]
                i += 1
            else:
                non_comment_part += line[i]
                i += 1

    # After processing the line, trim trailing whitespace from the code part
    # and append a newline to preserve the line count.
    processed_line = non_comment_part.rstrip() + '\n'
    return processed_line, in_multiline_comment


def process_file(input_path, strip_comments, processed_files=None):
    """
    Recursively processes a Lua file, handling #include directives and
    optionally stripping comments while preserving line numbers.
    """
    if processed_files is None:
        processed_files = set()

    if input_path in processed_files:
        return ""

    processed_files.add(input_path)
    output = []

    include_pattern = re.compile(r'^\s*#include\s+["\']?([^"\'\s]+)["\']?')

    try:
        with open(input_path, 'r', errors='ignore', encoding="utf-8") as file:
            in_multiline_comment = False
            for line_number, line in enumerate(file, 1):
                # First, check for #include directives, as they take precedence
                match = include_pattern.search(line)
                if match:
                    # An #include line is processed regardless of comment state
                    include_path = match.group(1)
                    resolved_path = resolve_path(input_path, include_path)
                    if os.path.exists(resolved_path):
                        included_content = process_file(resolved_path, strip_comments, processed_files)
                        if not included_content.endswith('\n'):
                            included_content += '\n'
                        
                        lead = line[:len(line) - len(line.lstrip(" "))]
                        
                        if not strip_comments:
                            output.append(lead + '-- ' + resolved_path + '{{{\n')
                        
                        output.append(included_content)
                        
                        if not strip_comments:
                            output.append(lead + '-- }}}' + resolved_path + '\n')
                    else:
                        print(f"Warning: Included file not found: {resolved_path} at line {line_number} in {input_path}. Skipping...")
                        resolved_path_sanitized = resolved_path.replace('\\', '\\\\')
                        input_path_sanitized = input_path.replace('\\', '\\\\')
                        output.append(f"fail(\"missing {resolved_path_sanitized} in {input_path_sanitized} at line {line_number}\")\n")
                    continue

                if strip_comments:
                    # Use the new, more aggressive stripping function
                    processed_line, in_multiline_comment = process_line_for_stripping(line, in_multiline_comment)
                    output.append(processed_line)
                else:
                    # If not stripping, append the line as is
                    output.append(line)

    except FileNotFoundError:
        print(f"Error: Input file not found at {input_path}")
        sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred while processing {input_path}: {e}")
        sys.exit(1)

    return ''.join(output)


def main():
    args = sys.argv[1:]
    
    # Check for the --strip flag
    strip_comments = "--strip" in args
    if strip_comments:
        args.remove("--strip")

    if len(args) != 2:
        print("Usage: python combinelua.py [--strip] <input_file> <output_file>")
        sys.exit(1)

    input_filename = args[0]
    output_filename = args[1]

    try:
        # Pass the strip_comments flag to the main processing function
        combined_content = process_file(input_filename, strip_comments)
        with open(output_filename, 'w', encoding='utf-8') as output_file:
            output_file.write(combined_content)
        
        status = "stripped and " if strip_comments else ""
        print(f"Successfully {status}combined scripts into {output_filename}")

    except Exception as e:
        print(f"An error occurred: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()