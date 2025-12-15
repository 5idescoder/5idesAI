#!/bin/bash

echo "🔄 Initiating 5ides System Reset..."

# 1. Wipe Memory
if [ -f ~/user_files/history.json ]; then
    rm ~/user_files/history.json
    echo "🗑️  Corrupt history file deleted."
else
    echo "💨 History was already clean."
fi

# 2. Restore Known-Good Chat Interface (Gemma Strict Mode)
echo "📝 Restoring ~/bin/chat to 'Gemma Strict' configuration..."

cat << 'PYTHON_EOF' > ~/bin/chat
#!/data/data/com.termux/files/usr/bin/python3
import os
import sys
import requests
import json
import readline
import glob
import re
import subprocess
from rich.console import Console
from rich.markdown import Markdown
from rich.panel import Panel
from rich.live import Live
from rich.text import Text
from bs4 import BeautifulSoup

# --- CONFIGURATION ---
API_URL = "http://127.0.0.1:8080/v1/chat/completions"
HISTORY_FILE = os.path.join(os.path.expanduser("~"), "user_files", "history.json")
MAX_HISTORY = 20

# INSTRUCTIONS
INSTRUCTIONS = (
    "INSTRUCTIONS:\n"
    "You are 5ides, an autonomous AI assistant on Termux.\n"
    "TOOLS:\n"
    "1. EXECUTE: <<<EXEC: command >>>\n"
    "2. SEARCH:  <<<SEARCH: query >>>\n"
    "3. SAVE:    <<<SAVE: filename>>> content <<<END>>>\n"
    "4. COPY:    <<<COPY: content >>>\n"
    "Use 'mkdir -p' for safety."
)

HISTORY = []
console = Console()

# --- UTILS ---
def clear_screen(): os.system('cls' if os.name == 'nt' else 'clear')

def print_banner():
    title = "[bold cyan]5ides 7ocal IDE[/bold cyan]"
    info = f"[dim white]Gemma Strict Mode • Agent Active[/dim white]"
    console.print(Panel(f"{title}\n{info}", border_style="blue", expand=False))

def init_history():
    """Forces the history to start with User -> Assistant."""
    global HISTORY
    HISTORY.clear()
    HISTORY.append({"role": "user", "content": INSTRUCTIONS + "\n\n[System Init: Please confirm readiness]"})
    HISTORY.append({"role": "assistant", "content": "I am ready to help."})

def load_history():
    global HISTORY
    if os.path.exists(HISTORY_FILE):
        try:
            with open(HISTORY_FILE, 'r') as f: 
                HISTORY = json.load(f)
            if not HISTORY or HISTORY[0]['role'] != 'user':
                init_history()
            console.print(f"[dim italic]Loaded history...[/dim italic]")
        except: init_history()
    else:
        init_history()

def save_history():
    os.makedirs(os.path.dirname(HISTORY_FILE), exist_ok=True)
    save_data = HISTORY[-MAX_HISTORY:] if len(HISTORY) > MAX_HISTORY else HISTORY
    # Ensure we don't slice off the start and break alternation
    if save_data and save_data[0]['role'] == 'assistant':
        save_data.pop(0) 
    with open(HISTORY_FILE, 'w') as f: json.dump(save_data, f, indent=2)

# --- TOOLS ---
def tool_web_search(query):
    console.print(f"[dim]🔎 Searching Web for: {query}...[/dim]")
    headers = { "User-Agent": "Mozilla/5.0 (Android 10; Mobile; rv:84.0)" }
    try:
        res = requests.post("https://html.duckduckgo.com/html/", data={'q': query}, headers=headers, timeout=10)
        soup = BeautifulSoup(res.text, 'html.parser')
        results = []
        for i, row in enumerate(soup.select('.result')):
            if i >= 3: break
            title = row.select_one('.result__title').get_text(strip=True)
            link = row.select_one('.result__a')['href']
            results.append(f"Title: {title}\nLink: {link}\n")
        return "\n".join(results) if results else "No results."
    except Exception as e: return f"Search Error: {e}"

def tool_exec(command):
    console.print(f"\n[bold yellow]⚠️  AI Request:[/bold yellow] [on black]{command}[/on black]")
    if input("Allow? (y/n) ❯ ").lower().strip() != 'y': return "User denied permission."
    try:
        res = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=60, executable="/data/data/com.termux/files/usr/bin/bash")
        out = res.stdout + res.stderr
        if not out: out = "[Done (No Output)]"
        console.print(Panel(out.strip(), title="Output", border_style="green"))
        return out
    except Exception as e: return f"Error: {e}"

def tool_save(filename, content):
    try:
        filepath = os.path.expanduser(filename)
        os.makedirs(os.path.dirname(filepath), exist_ok=True)
        with open(filepath, 'w', encoding='utf-8') as f: f.write(content)
        console.print(f"[bold green]💾 Saved:[/bold green] {filepath}")
        return f"Successfully saved {filename}"
    except Exception as e: return f"Error saving: {e}"

def tool_copy(content):
    try:
        p = subprocess.Popen(['termux-clipboard-set'], stdin=subprocess.PIPE)
        p.communicate(input=content.strip().encode('utf-8'))
        console.print("[bold magenta]📋 Copied to clipboard![/bold magenta]")
    except: console.print("[red]Install termux-api for clipboard.[/red]")

def generate_command(req):
    console.print("[dim]Generating command...[/dim]")
    temp_hist = [{"role": "user", "content": "Convert to bash block using '~' and 'mkdir -p': " + req}]
    try:
        r = requests.post(API_URL, json={"messages": temp_hist, "stream": False}, timeout=30)
        c = r.json()['choices'][0]['message']['content']
        m = re.search(r"```(?:bash|sh)?\s*\n?(.*?)\s*```", c, re.DOTALL)
        return m.group(1).strip() if m else c.strip()
    except: return None

# --- COMMANDS ---
def cmd_help(args):
    txt = """
    [green]/new[/green]             Reset Chat (Fixes Errors)
    [green]/copy[/green]            Copy last response
    [green]/exec <text>[/green]     Smart Execution
    [green]/web <query>[/green]     Search Web
    [green]/view <file>[/green]     View file
    """
    console.print(Panel(txt, title="Commands"))

def cmd_copy(args):
    last_msg = None
    for msg in reversed(HISTORY):
        if msg['role'] == 'assistant':
            last_msg = msg['content']
            break
    if last_msg: tool_copy(last_msg)

def cmd_view(args):
    if not args: return console.print("[red]Usage: /view <file>[/red]")
    path = os.path.expanduser(args)
    if os.path.exists(path):
        with open(path, 'r') as f: console.print(Panel(f.read(), title=path))
        if HISTORY[-1]['role'] == 'assistant':
            HISTORY.append({"role": "user", "content": f"I viewed {path}."})
        save_history()

def cmd_smart_exec(args):
    c = generate_command(args)
    if c:
        console.print(Panel(c, title="Generated", border_style="cyan"))
        if input("Run? (y/n) ❯ ") == 'y':
            if HISTORY[-1]['role'] == 'assistant':
                HISTORY.append({"role": "user", "content": f"I ran: {c}"})
            out = tool_exec(c)
            HISTORY[-1]['content'] += f"\n\nOutput:\n{out}"
            save_history()

def cmd_web(args):
    res = tool_web_search(args)
    if HISTORY[-1]['role'] == 'assistant':
        HISTORY.append({"role":"user", "content":f"Search results for '{args}':\n{res}"})
    save_history()

def cmd_new(args):
    clear_screen(); print_banner(); 
    init_history()
    save_history()
    console.print("[green]Session Wiped & Fixed.[/green]")

COMMANDS = {'/help':cmd_help, '/copy':cmd_copy, '/view':cmd_view, 
            '/exec':cmd_smart_exec, '/web':cmd_web, '/exit':lambda x:sys.exit(0),
            '/new': cmd_new}

# --- MAIN ---
def stream_response(messages):
    context = messages[-MAX_HISTORY:]
    try:
        r = requests.post(API_URL, json={"messages":context, "mode":"chat", "stream":True}, stream=True, timeout=120)
        if r.status_code!=200:
            console.print(f"[red]Server Error {r.status_code}: {r.text}[/red]")
            return None
        full=""
        with Live(Text(""), refresh_per_second=15, console=console) as live:
            for l in r.iter_lines():
                if not l: continue
                l = l.decode('utf-8')[6:]
                if l=="[DONE]": break
                try:
                    j=json.loads(l)
                    c=j['choices'][0]['delta'].get('content','') if 'choices' in j else ""
                    full+=c; live.update(Markdown(full))
                except: continue
        return full
    except Exception as e:
        console.print(f"[red]Connection Error: {e}[/red]")
        return None

def main():
    clear_screen(); print_banner(); load_history()
    
    def completer(text, state):
        line = readline.get_line_buffer()
        if not line.startswith(('/view', '/exec')): return None
        if '~' in text: text = os.path.expanduser(text)
        return (glob.glob(text+'*')+[None])[state]
    readline.set_completer_delims(' \t\n;')
    readline.parse_and_bind("tab: complete")
    readline.set_completer(completer)

    while True:
        try:
            console.print("\n[bold green]User[/bold green]")
            u = input("❯ ").strip()
            if not u: continue
            
            if u.startswith('/'):
                p=u.split(' ',1); c=p[0].lower(); a=p[1] if len(p)>1 else ""
                if c in COMMANDS: COMMANDS[c](a); continue
            
            # STRICT ALTERNATION CHECK
            if HISTORY and HISTORY[-1]['role'] == 'user':
                HISTORY[-1]['content'] += f"\n\n{u}"
            else:
                HISTORY.append({"role":"user","content":u})

            console.print("\n[bold cyan]5ides[/bold cyan]")
            
            rep = stream_response(HISTORY)
            if rep:
                HISTORY.append({"role":"assistant","content":rep})
                
                tool_output = ""
                s = re.search(r'<<<SEARCH:(.*?)>>>', rep)
                if s:
                    res = tool_web_search(s.group(1).strip())
                    tool_output += f"Search Results:\n{res}\n"

                x = re.search(r'<<<EXEC:(.*?)>>>', rep)
                if x:
                    out = tool_exec(x.group(1).strip())
                    tool_output += f"Command Output:\n{out}\n"

                sv = re.search(r'<<<SAVE:(.*?)>>>\n?(.*?)\n?<<<END>>>', rep, re.DOTALL)
                if sv: tool_save(sv.group(1).strip(), sv.group(2))

                cp = re.search(r'<<<COPY:(.*?)>>>', rep, re.DOTALL)
                if cp: tool_copy(cp.group(1).strip())

                if tool_output:
                    HISTORY.append({"role": "user", "content": f"System Report:\n{tool_output}"})
                    console.print("\n[bold cyan]5ides (Thinking...)[/bold cyan]")
                    f_up = stream_response(HISTORY)
                    if f_up: HISTORY.append({"role":"assistant", "content":f_up})

                save_history()
        except KeyboardInterrupt: save_history(); break

if __name__ == "__main__": main()
