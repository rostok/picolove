import sys
import os
import re
from collections import Counter

# Globalny cache dla mapowania linii: { "filename.p8": { combined_line: ("orig_file", orig_line) } }
file_mappings = {}

def parse_combined_file(filepath):
    """
    Czyta połączony plik Lua i buduje słownik mapujący 
    numer linii z pliku combined na (oryginalny_plik, oryginalna_linia).
    """
    mapping = {}
    # Stos symulujący zagnieżdżenia. Na dnie znajduje się plik główny.
    stack = [{"file": os.path.basename(filepath), "line": 0}]
    
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for combined_line_idx, line in enumerate(f, 1):
                # Szukamy znaczników dodanych przez combinelua.py
                match_start = re.search(r'^(\s*)--\s*(.+?)\{\{\{', line)
                match_end = re.search(r'^(\s*)--\s*\}\}\}(.+)', line)
                
                if match_start:
                    included_file = match_start.group(2).strip()
                    # Znacznik początku zastępuje dyrektywę #include w pliku nadrzędnym
                    stack[-1]["line"] += 1
                    mapping[combined_line_idx] = (stack[-1]["file"], stack[-1]["line"])
                    # Wchodzimy do nowego pliku
                    stack.append({"file": included_file, "line": 0})
                
                elif match_end:
                    # Zamykamy aktualny plik
                    stack.pop()
                    if not stack: # Fallback w razie uszkodzonych znaczników
                        stack.append({"file": os.path.basename(filepath), "line": combined_line_idx})
                    # Marker zamykający istnieje tylko w połączonym pliku, przypisujemy go do aktualnej linii rodzica
                    mapping[combined_line_idx] = (stack[-1]["file"], stack[-1]["line"])
                
                else:
                    # Zwykła linia kodu
                    stack[-1]["line"] += 1
                    mapping[combined_line_idx] = (stack[-1]["file"], stack[-1]["line"])
        return mapping
    except Exception as e:
        print(f"Ostrzeżenie: Nie udało się przetworzyć połączonego pliku {filepath}: {e}")
        return None

def find_file(filename, base_dir):
    """Próbuje inteligentnie zlokalizować połączony plik na dysku."""
    if os.path.exists(filename): return filename
    
    path = os.path.join(base_dir, filename)
    if os.path.exists(path): return path
    
    # Heurystyka: szukamy katalog wyżej lub w podfolderze 'love'
    curr = os.path.abspath(base_dir)
    for _ in range(3):
        curr = os.path.dirname(curr)
        # Bezpośrednio
        p = os.path.join(curr, filename)
        if os.path.exists(p): return p
        # W katalogu love
        p_love = os.path.join(curr, 'love', filename)
        if os.path.exists(p_love): return p_love
        
    return None

def translate_line(raw_filename, raw_line, log_dir):
    """Zamienia plik_combined:linia na oryginalny_plik:linia."""
    if raw_filename not in file_mappings:
        actual_path = find_file(raw_filename, log_dir)
        if actual_path:
            file_mappings[raw_filename] = parse_combined_file(actual_path)
        else:
            file_mappings[raw_filename] = None # Zapisujemy None, by nie szukać ponownie
            
    mapping = file_mappings[raw_filename]
    if mapping:
        return mapping.get(raw_line, (raw_filename, raw_line))
    return raw_filename, raw_line

def main():
    if len(sys.argv) < 2:
        print("Użycie: python analyze_jit.py <plik_logu.txt>")
        sys.exit(1)

    log_filename = sys.argv[1]
    log_dir = os.path.dirname(os.path.abspath(log_filename))

    if not os.path.exists(log_filename):
        print(f"Nie można otworzyć pliku logu: {log_filename}")
        sys.exit(1)

    flushes = 0
    successes = 0
    aborts = 0
    reasons = Counter()

    with open(log_filename, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()
            
            if "[TRACE flush]" in line:
                flushes += 1
            
            elif "[TRACE ---" in line:
                aborts += 1
                
                # Typowy format logu JIT: [TRACE --- context -- reason]
                parts = line.split(" -- ")
                if len(parts) >= 2:
                    reason = parts[-1].rstrip("]")
                    
                    context = " -- ".join(parts[:-1])
                    context = re.sub(r"^\[TRACE\s+---\s+", "", context)
                    
                    # Wyciągamy plik i linię z kontekstu
                    file_match = re.search(r'"?([^"]+\.[a-zA-Z0-9]+)"?:(\d+)', context)
                    
                    if file_match:
                        raw_filename = file_match.group(1)
                        raw_line = int(file_match.group(2))
                        
                        # Tutaj dzieje się magia tłumaczenia 
                        orig_file, orig_line = translate_line(raw_filename, raw_line, log_dir)
                        
                        # Zamieniamy "combined.p8:9999" na "src/view.lua:42" w tekście
                        context_replaced = context[:file_match.start()] + f'"{orig_file}":{orig_line}' + context[file_match.end():]
                        key = f"- {context_replaced} -- {reason}"
                    else:
                        key = f"- {context} -- {reason}"
                        
                    # Oczyszczamy z adresów pamięci, żeby ładnie pogrupować np. funkcje anonimowe
                    key = re.sub(r" at 0x[0-9a-fA-F]+", "", key)
                    
                    reasons[key] += 1
                
            elif re.search(r"\[TRACE\s+\d+", line):
                successes += 1

    print(f"=== RAPORT: {log_filename} ===")
    print(f"Zbudowane ślady (Sukcesy) : {successes}")
    print(f"Przerwane ślady (Aborts)  : {aborts}")
    print(f"Zresetowanie JIT (FLUSH)  : {flushes}")
    print("-" * 33)
    print("Główne powody przerwania kompilacji (TOP 10):")

    for reason, count in reasons.most_common(10):
        print(f"{count:6d} x | {reason}")
    print()

if __name__ == "__main__":
    main()