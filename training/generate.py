#!/usr/bin/env python3
"""Generates Needle fine-tuning data for aiterm's actions.

Each example shows the correct tool plus confusable and random distractors,
because the full tool list (~1.7k tokens) would overflow the 1024-token
training window. Deterministic for a given --seed. Never emits a phrasing
from the held-out eval set (checked at the end).

  python3 training/generate.py --out train.jsonl [--per-tool 140] [--seed 0]
"""
import argparse, json, os, random, re

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = {t["name"]: t for t in json.load(open(os.path.join(HERE, "..", "assets", "needle_tools.json")))}

PACKAGES = ["node", "nodejs", "npm", "python", "python3", "pip", "git", "curl", "wget", "vim", "nano",
            "gcc", "make", "go", "rust", "cargo", "ripgrep", "jq", "htop", "openssh", "zip", "unzip",
            "bash", "zsh", "neovim", "tmux", "ffmpeg", "sqlite", "redis", "openjdk", "ruby", "php",
            "deno", "yarn", "pnpm", "clang", "cmake", "perl", "lua", "fzf", "bat", "tree", "gh",
            "postgresql", "imagemagick", "httpie", "rsync", "nmap", "lsof", "file", "less"]
FILES = ["notes.txt", "todo.md", "index.js", "main.py", "app.ts", "README.md", "config.json",
         "settings.yaml", ".env", "server.js", "style.css", "index.html", "data.csv", "run.sh",
         "Makefile", "package.json", "build.gradle", "report.pdf", "photo.jpg", "backup.zip",
         "log.txt", "test.py", "utils.go", "lib.rs", "schema.sql", "Dockerfile", "notes/ideas.md"]
FOLDERS = ["src", "projects", "app", "docs", "backup", "Download", "Documents", "Pictures",
           "notes", "build", "dist", "tests", "scripts", "assets", "old", "tmp", "work", "lib"]
TYPES = ["python", "javascript", "js", "typescript", "pdf", "pdfs", "images", "photos", "videos",
         "markdown", "json", "csv", "log", "shell scripts", "html", "css", "go", "rust", "zip"]
NAMES = ["config", "readme", "test", "main", "index", "backup", "report", "invoice", "todo", "draft"]
TEXT = ["TODO", "password", "api_key", "useState", "express", "import requests", "FIXME",
        "console.log", "localhost", "version", "error", "deprecated"]
PROCS = ["node", "python", "vite", "npm", "java", "nginx", "redis", "ssh", "claude", "top", "server"]
MSGS = ["fix login bug", "wip", "initial commit", "add readme", "update deps", "refactor api",
        "add tests", "fix typo", "release 1.0", "remove unused code", "add dark mode"]
REPOS = ["https://github.com/torvalds/linux", "github.com/facebook/react", "https://github.com/x/app",
         "https://gitlab.com/team/tool.git", "github.com/arshan1019/aiterm", "https://github.com/me/dotfiles"]
URLS = ["https://example.com/a.zip", "https://x.org/file.tar.gz", "https://cdn.site.io/data.csv",
        "https://example.com/image.png", "https://releases.app.dev/v2/app.apk", "https://site.net/doc.pdf"]

LEAD = ["", "", "", "please ", "can you ", "could you ", "i want to ", "help me ", "pls ", "now "]
TAIL = ["", "", "", " please", " for me", " now", " thanks"]

# Tools that are easy to confuse; used as hard negatives.
CONFUSABLE = {
    "install_package": ["install_dependencies", "update_packages", "create_file", "remove_package", "download_file"],
    "remove_package": ["delete_file", "kill_process", "install_package", "update_packages"],
    "update_packages": ["install_package", "install_dependencies", "list_files", "git_push"],
    "install_dependencies": ["install_package", "run_script", "update_packages"],
    "run_script": ["start_claude", "install_dependencies", "kill_process", "show_processes"],
    "create_folder": ["create_file", "change_directory", "run_script", "show_in_files"],
    "create_file": ["create_folder", "edit_file", "show_file"],
    "delete_file": ["remove_package", "move_file", "kill_process"],
    "move_file": ["copy_file", "change_directory", "delete_file"],
    "copy_file": ["move_file", "create_file", "download_file"],
    "show_file": ["edit_file", "list_files", "find_files", "search_text"],
    "edit_file": ["show_file", "create_file", "move_file"],
    "list_files": ["find_big_files", "show_file", "current_folder", "find_files", "show_in_files"],
    "change_directory": ["list_files", "show_in_files", "current_folder", "move_file"],
    "current_folder": ["list_files", "change_directory", "free_space"],
    "find_files": ["search_text", "list_files", "find_big_files"],
    "search_text": ["find_files", "show_file", "git_status"],
    "free_space": ["find_big_files", "list_files", "show_processes"],
    "find_big_files": ["free_space", "list_files", "find_files"],
    "show_processes": ["git_status", "list_files", "kill_process", "free_space"],
    "kill_process": ["delete_file", "remove_package", "show_processes"],
    "git_status": ["show_processes", "list_files", "git_commit"],
    "git_commit": ["git_push", "git_status", "create_file"],
    "git_push": ["git_commit", "download_file", "git_clone"],
    "git_clone": ["download_file", "git_push", "install_package"],
    "download_file": ["git_clone", "install_package", "copy_file"],
    "start_claude": ["run_script", "install_package", "open_tab"],
    "set_font_size": ["set_theme", "open_tab"],
    "set_theme": ["set_font_size", "open_tab"],
    "open_tab": ["show_in_files", "change_directory", "set_theme"],
    "restart_shell": ["kill_process", "run_script", "open_tab"],
    "show_in_files": ["change_directory", "list_files", "open_tab"],
}

# Templates: (text with {slots}, function(slots) -> arguments). Slot values are
# drawn per example; `{p}` package, `{f}` file, `{d}` folder, etc.
def A(**kw):
    return kw

T = {
 "install_package": [
  ("install {p}", lambda s: A(name=s["p"])), ("add {p}", lambda s: A(name=s["p"])),
  ("get {p}", lambda s: A(name=s["p"])), ("get me {p}", lambda s: A(name=s["p"])),
  ("i need {p}", lambda s: A(name=s["p"])), ("setup {p}", lambda s: A(name=s["p"])),
  ("set up {p}", lambda s: A(name=s["p"])), ("install the {p} package", lambda s: A(name=s["p"])),
  ("download and install {p}", lambda s: A(name=s["p"])), ("can i get {p}", lambda s: A(name=s["p"])),
  ("install {p} for me", lambda s: A(name=s["p"])), ("apk add {p}", lambda s: A(name=s["p"])),
  ("install {p} and {p2}", lambda s: A(name=s["p"])),
 ],
 "remove_package": [
  ("uninstall {p}", lambda s: A(name=s["p"])), ("remove the {p} package", lambda s: A(name=s["p"])),
  ("get rid of {p}", lambda s: A(name=s["p"])), ("i don't need {p} anymore, uninstall it", lambda s: A(name=s["p"])), ("remove {p} from the system", lambda s: A(name=s["p"])),
  ("purge {p}", lambda s: A(name=s["p"])),
 ],
 "update_packages": [
  ("update everything", lambda s: A()), ("upgrade all packages", lambda s: A()),
  ("update my system", lambda s: A()), ("update packages", lambda s: A()),
  ("upgrade the system", lambda s: A()),
  ("check for updates and install them", lambda s: A()), ("update all my software", lambda s: A()),
  ],
 "install_dependencies": [
  ("install dependencies", lambda s: A()), ("npm install", lambda s: A()),
  ("install the project's packages", lambda s: A()), ("install the deps", lambda s: A()),
  ("get the node modules", lambda s: A()),
  ("install everything in package.json", lambda s: A()), ("install project requirements", lambda s: A()),
 ],
 "run_script": [
  ("start the dev server", lambda s: A(script="dev")), ("run dev", lambda s: A(script="dev")),
  ("serve the app locally", lambda s: A(script="dev")),
  ("run the tests", lambda s: A(script="test")), ("test the project", lambda s: A(script="test")),
  ("run my unit tests", lambda s: A(script="test")),
  ("build the project", lambda s: A(script="build")), ("make a production build", lambda s: A(script="build")), ("npm start", lambda s: A(script="start")),
  ("start the app", lambda s: A(script="start")), ("run the project", lambda s: A(script="start")),
 ],
 "create_folder": [
  ("create a folder called {d}", lambda s: A(name=s["d"])), ("make a directory named {d}", lambda s: A(name=s["d"])),
  ("mkdir {d}", lambda s: A(name=s["d"])), ("new folder {d}", lambda s: A(name=s["d"])),
  ("make a new folder {d}", lambda s: A(name=s["d"])), ("create directory {d}", lambda s: A(name=s["d"])), ("add a folder {d}", lambda s: A(name=s["d"])),
  ("create a folder", lambda s: A()), ("make a new directory", lambda s: A()), ("new folder", lambda s: A()),
 ],
 "create_file": [
  ("create a file called {f}", lambda s: A(name=s["f"])), ("make a new file {f}", lambda s: A(name=s["f"])),
  ("touch {f}", lambda s: A(name=s["f"])), ("create {f}", lambda s: A(name=s["f"])),
  ("new file {f}", lambda s: A(name=s["f"])), ("create a file", lambda s: A()), ("make an empty file", lambda s: A()),
 ],
 "delete_file": [
  ("delete {f}", lambda s: A(name=s["f"])), ("remove {f}", lambda s: A(name=s["f"])), ("rm {f}", lambda s: A(name=s["f"])),
  ("erase the file {f}", lambda s: A(name=s["f"])),
  ("delete the {d} folder", lambda s: A(name=s["d"])), ("remove the {d} directory", lambda s: A(name=s["d"])),
  ("get rid of {f}", lambda s: A(name=s["f"])),
 ],
 "move_file": [
  ("rename {f} to {f2}", lambda s: A(source=s["f"], destination=s["f2"])),
  ("move {f} to {d}", lambda s: A(source=s["f"], destination=s["d"])),
  ("move {f} into {d}", lambda s: A(source=s["f"], destination=s["d"])),
  ("mv {f} {d}", lambda s: A(source=s["f"], destination=s["d"])),
 ],
 "copy_file": [
  ("copy {f} to {f2}", lambda s: A(source=s["f"], destination=s["f2"])),
  ("copy {f} into {d}", lambda s: A(source=s["f"], destination=s["d"])),
  ("duplicate {f} as {f2}", lambda s: A(source=s["f"], destination=s["f2"])),
  ("cp {f} {d}", lambda s: A(source=s["f"], destination=s["d"])),
 ],
 "show_file": [
  ("show me {f}", lambda s: A(name=s["f"])), ("print {f}", lambda s: A(name=s["f"])), ("cat {f}", lambda s: A(name=s["f"])),
  ("what does {f} say", lambda s: A(name=s["f"])), ("read {f}", lambda s: A(name=s["f"])), ("display the contents of {f}", lambda s: A(name=s["f"])),
  ("what's inside {f}", lambda s: A(name=s["f"])), ("view {f}", lambda s: A(name=s["f"])),
 ],
 "edit_file": [
  ("edit {f}", lambda s: A(name=s["f"])), ("open {f} in an editor", lambda s: A(name=s["f"])),
  ("change the contents of {f}", lambda s: A(name=s["f"])), ("vim {f}", lambda s: A(name=s["f"])),
  ("make changes to {f}", lambda s: A(name=s["f"])), ("nano {f}", lambda s: A(name=s["f"])),
 ],
 "list_files": [
  ("list files", lambda s: A()), ("list all files", lambda s: A()), ("show files", lambda s: A()), ("ls", lambda s: A()),
  ("what's in this folder", lambda s: A()), ("show hidden files", lambda s: A()),
  ("what is in the {d} folder", lambda s: A(path=s["d"])),
  ("ls {d}", lambda s: A(path=s["d"])),
  ("what files are in {d}", lambda s: A(path=s["d"])),
 ],
 "change_directory": [
  ("go to {d}", lambda s: A(path=s["d"])), ("cd into {d}", lambda s: A(path=s["d"])), ("cd {d}", lambda s: A(path=s["d"])),
  ("open the {d} folder in the terminal", lambda s: A(path=s["d"])), ("enter {d}", lambda s: A(path=s["d"])),
  ("go up one folder", lambda s: A(path="..")), ("cd ..", lambda s: A(path="..")),
  ("go home", lambda s: A(path="~")), ("go to my home folder", lambda s: A(path="~")),
 ],
 "current_folder": [
  ("where am i", lambda s: A()), ("what folder am i in", lambda s: A()), ("show current directory", lambda s: A()),
  ("pwd", lambda s: A()), ("print the working directory", lambda s: A()),
 ],
 "find_files": [
  ("find all {t} files", lambda s: A(type=s["t"])), ("where are my {t}", lambda s: A(type=s["t"])),
  ("search for {t}", lambda s: A(type=s["t"])), ("find {t} files in {d}", lambda s: A(type=s["t"], path=s["d"])), ("find files named {n}", lambda s: A(name=s["n"])), ("look for a file called {n}", lambda s: A(name=s["n"])),
  ("where is the {n} file", lambda s: A(name=s["n"])),
 ],
 "search_text": [
  ("search for {q} in my code", lambda s: A(query=s["q"])), ("grep for {q}", lambda s: A(query=s["q"])),
  ("which files mention {q}", lambda s: A(query=s["q"])), ("look for {q} inside files in {d}", lambda s: A(query=s["q"], path=s["d"])),
  ("find the text {q}", lambda s: A(query=s["q"])),
 ],
 "free_space": [
  ("how much space is left", lambda s: A()), ("how much disk space do i have", lambda s: A()),
  ("is my storage full", lambda s: A()), ("df", lambda s: A()), ("show disk usage summary", lambda s: A()),
 ],
 "find_big_files": [
  ("what is taking up space", lambda s: A()), ("show me the biggest files", lambda s: A()),
  ("what's eating my storage", lambda s: A()), ("find large files in {d}", lambda s: A(path=s["d"])), ("show the biggest files in {d}", lambda s: A(path=s["d"])),
 ],
 "show_processes": [
  ("what is running", lambda s: A()), ("show running processes", lambda s: A()), ("what programs are using cpu", lambda s: A()),
  ("ps", lambda s: A()), ("show me what's using memory", lambda s: A()),
 ],
 "kill_process": [
  ("stop {r}", lambda s: A(name=s["r"])), ("kill {r}", lambda s: A(name=s["r"])), ("close the {r} process", lambda s: A(name=s["r"])),
  ("shut down {r}", lambda s: A(name=s["r"])), ("pkill {r}", lambda s: A(name=s["r"])),
 ],
 "git_status": [
  ("git status", lambda s: A()), ("what changed", lambda s: A()), ("show my changes", lambda s: A()),
  ("what files did i modify", lambda s: A()),
 ],
 "git_commit": [
  ("commit everything with message {m}", lambda s: A(message=s["m"])), ("commit with message {m}", lambda s: A(message=s["m"])),
  ("save my work to git as {m}", lambda s: A(message=s["m"])), ("commit my changes: {m}", lambda s: A(message=s["m"])),
  ("git commit -m {m}", lambda s: A(message=s["m"])), ("commit saying {m}", lambda s: A(message=s["m"])),
 ],
 "git_push": [
  ("push my changes", lambda s: A()), ("push to github", lambda s: A()), ("upload my commits", lambda s: A()),
  ("git push", lambda s: A()), ],
 "git_clone": [
  ("clone {g}", lambda s: A(url=s["g"])), ("download the repo {g}", lambda s: A(url=s["g"])),
  ("git clone {g}", lambda s: A(url=s["g"])),
  ],
 "download_file": [
  ("download {u}", lambda s: A(url=s["u"])), ("wget {u}", lambda s: A(url=s["u"])), ("get this file {u}", lambda s: A(url=s["u"])),
 ],
 "start_claude": [
  ("open claude", lambda s: A()), ("start claude code", lambda s: A()), ("i want to use the ai assistant", lambda s: A()), ("run claude", lambda s: A()), ("ask claude for help with code", lambda s: A()),
 ],
 "set_font_size": [
  ("make the text bigger", lambda s: A(change="bigger")), ("bigger font", lambda s: A(change="bigger")),
  ("increase font size", lambda s: A(change="bigger")), ("zoom in", lambda s: A(change="bigger")),
  ("make the text smaller", lambda s: A(change="smaller")), ("smaller font", lambda s: A(change="smaller")),
  ("decrease the font size", lambda s: A(change="smaller")), ("zoom out", lambda s: A(change="smaller")),
 ],
 "set_theme": [
  ("switch to light theme", lambda s: A(theme="light")), ("light mode", lambda s: A(theme="light")),
  ("make it bright", lambda s: A(theme="light")), ("switch to dark theme", lambda s: A(theme="dark")),
  ("dark mode", lambda s: A(theme="dark")), ("turn on dark mode", lambda s: A(theme="dark")),
 ],
 "open_tab": [
  ("open the files tab", lambda s: A(tab="files")), ("show the file browser", lambda s: A(tab="files")),
  ("go to settings", lambda s: A(tab="settings")), ("open settings", lambda s: A(tab="settings")),
  ("back to the terminal", lambda s: A(tab="terminal")), ("show the terminal", lambda s: A(tab="terminal")),
 ],
 "restart_shell": [
  ("restart the shell", lambda s: A()), ("restart the terminal", lambda s: A()), ("start a fresh session", lambda s: A()),
  ("the terminal is stuck, restart it", lambda s: A()), ("reset the terminal session", lambda s: A()),
 ],
 "show_in_files": [
  ("show {d} in the file browser", lambda s: A(path=s["d"])), ("open {d} in files", lambda s: A(path=s["d"])),
  ("browse the {d} folder", lambda s: A(path=s["d"])), ("show my {d} folder in the files tab", lambda s: A(path=s["d"])),
 ],
}

NONE = ["whats the weather", "tell me a joke", "delete everything", "send an email to bob", "play some music",
        "who are you", "translate hello to french",
        "call mom", "what is the capital of france", "write me a poem", "set an alarm for 7", "how are you",
        "format my phone", "hack my neighbor's wifi", "turn on the flashlight", "book a flight", "what's 2+2",
        "show me cat pictures", "erase all my data", "text alice i'm late", "open instagram"]

def fill(rng):
    p, p2 = rng.sample(PACKAGES, 2)
    f, f2 = rng.sample(FILES, 2)
    return {"p": p, "p2": p2, "f": f, "f2": f2, "d": rng.choice(FOLDERS), "t": rng.choice(TYPES),
            "n": rng.choice(NAMES), "q": rng.choice(TEXT), "r": rng.choice(PROCS), "m": rng.choice(MSGS),
            "g": rng.choice(REPOS), "u": rng.choice(URLS)}

def phrase(rng, text):
    s = rng.choice(LEAD) + text + rng.choice(TAIL)
    if rng.random() < 0.15:
        s = s[0].upper() + s[1:]
    if rng.random() < 0.1:
        s += "?" if s.startswith(("what", "where", "which", "how", "is ", "can", "could")) else "."
    return s

def toolset(rng, correct):
    """Correct tool (if any) + up to 2 confusable + random distractors, 6 total, shuffled."""
    names = set([correct]) if correct else set()
    if correct:
        names.update(rng.sample(CONFUSABLE[correct], min(2, len(CONFUSABLE[correct]))))
    while len(names) < 6:
        names.add(rng.choice(list(TOOLS)))
    out = [TOOLS[n] for n in names]
    rng.shuffle(out)
    return out

def reasoning(query, call):
    if not call["arguments"]:
        return f"'{query}' -> {call['name']}, no arguments."
    parts = ", ".join(f"{k} '{v}'" for k, v in call["arguments"].items())
    return f"'{query}' -> {call['name']} with {parts}."

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--per-tool", type=int, default=140)
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()
    rng = random.Random(args.seed)
    missing = set(TOOLS) - set(T)
    assert not missing, f"no templates for {missing}"

    holdout = set()
    hp = os.path.join(HERE, "holdout.tsv")
    for l in open(hp):
        if l.strip() and not l.startswith("#"):
            holdout.add(re.sub(r"[^a-z0-9 ]", "", l.split("\t")[0].lower()).strip())

    rows, seen = [], set()
    for tool, templates in T.items():
        made, tries = 0, 0
        while made < args.per_tool and tries < args.per_tool * 30:
            tries += 1
            text, argf = rng.choice(templates)
            slots = fill(rng)
            query = phrase(rng, text.format(**slots))
            key = re.sub(r"[^a-z0-9 ]", "", query.lower()).strip()
            if key in seen or key in holdout:
                continue
            seen.add(key)
            call = {"name": tool, "arguments": argf(slots)}
            rows.append({"query": query, "tools": toolset(rng, tool), "answers": [call],
                         "reasoning": reasoning(query, call)})
            made += 1
    n_none = len(rows) // 7
    for _ in range(n_none):
        query = phrase(rng, rng.choice(NONE))
        rows.append({"query": query, "tools": toolset(rng, None), "answers": [],
                     "reasoning": f"'{query}' matches none of the tools."})
    rng.shuffle(rows)
    with open(args.out, "w") as fh:
        for r in rows:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"{len(rows)} examples ({n_none} no-call) -> {args.out}")

if __name__ == "__main__":
    main()
