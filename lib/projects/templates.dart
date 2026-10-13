/// Starter projects. Kept small: enough for an agent (or the user) to
/// build on, with a .gitignore so dependencies never get committed.
class ProjectTemplate {
  const ProjectTemplate(this.id, this.name, this.description, this.files);
  final String id;
  final String name;
  final String description;

  /// Relative path → contents; `{{name}}` / `{{slug}}` are filled in.
  final Map<String, String> files;
}

const projectTemplates = [
  ProjectTemplate('node', 'Node.js', 'A Node.js app with npm scripts', {
    'package.json': '{\n  "name": "{{slug}}",\n  "version": "0.1.0",\n  "private": true,\n  "type": "module",\n'
        '  "scripts": {\n    "start": "node index.js"\n  }\n}\n',
    'index.js': "console.log('Hello from {{name}}');\n",
    'README.md': '# {{name}}\n\nRun with `npm start`.\n',
    '.gitignore': 'node_modules/\n.env\n',
  }),
  ProjectTemplate('python', 'Python', 'A Python script with a requirements file', {
    'main.py': 'def main():\n    print("Hello from {{name}}")\n\n\nif __name__ == "__main__":\n    main()\n',
    'requirements.txt': '',
    'README.md': '# {{name}}\n\nRun with `python3 main.py`.\n',
    '.gitignore': '__pycache__/\n.venv/\n.env\n',
  }),
  ProjectTemplate('web', 'Web page', 'HTML, CSS and JavaScript', {
    'index.html': '<!doctype html>\n<html lang="en">\n<head>\n  <meta charset="utf-8">\n'
        '  <meta name="viewport" content="width=device-width, initial-scale=1">\n  <title>{{name}}</title>\n'
        '  <link rel="stylesheet" href="style.css">\n</head>\n<body>\n  <h1>{{name}}</h1>\n'
        '  <script src="script.js"></script>\n</body>\n</html>\n',
    'style.css': 'body {\n  font-family: system-ui, sans-serif;\n  margin: 2rem;\n}\n',
    'script.js': "console.log('{{name}} loaded');\n",
    'README.md': '# {{name}}\n\nPreview with `python3 -m http.server 8000`.\n',
    '.gitignore': '.env\n',
  }),
];
