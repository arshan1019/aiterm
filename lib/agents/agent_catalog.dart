/// AI coding agents aiterm installs in one tap, with everything they need.
///
/// aiterm's purpose is running these agents natively on a phone; the Linux
/// underneath is how. Each recipe lists the Alpine packages an agent relies
/// on and the official install command, run as ordinary shell steps.
library;

class AgentStep {
  const AgentStep(this.label, this.script);

  /// Shown while the step runs ("Installing dependencies…").
  final String label;

  /// POSIX sh, stopping at the first error.
  final String script;
}

class AgentRecipe {
  const AgentRecipe({
    required this.id,
    required this.name,
    required this.vendor,
    required this.tagline,
    required this.packages,
    required this.install,
    required this.command,
  });

  final String id;
  final String name;
  final String vendor;
  final String tagline;

  /// Alpine packages the agent needs at runtime.
  final List<String> packages;

  /// The vendor's own install command.
  final String install;

  /// The program to run; it handles sign-in on first start.
  final String command;

  /// Everything to install: the base userland plus the agent's own needs.
  List<String> get allPackages => {...baseUserland, ...packages}.toList();

  AgentStep get dependencies =>
      AgentStep('Installing dependencies', 'set -e\napk update -q\napk add -q --no-cache ${allPackages.join(' ')}');

  List<AgentStep> get steps => [
        dependencies,
        AgentStep('Installing $name', 'set -e\n$install'),
      ];
}

/// What agents expect of a Linux dev machine. Alpine's defaults are
/// BusyBox's cut-down tools; agents (and the commands they run) assume the
/// standard ones: procps `ps` (Codex reads `ps -p … -o lstart=`), GNU
/// coreutils/findutils/grep/sed/diff, less, and ssh for git remotes.
const baseUserland = [
  'procps-ng', 'coreutils', 'findutils', 'grep', 'sed', 'diffutils', 'less', 'openssh-client', 'ca-certificates',
];

const agentCatalog = [
  AgentRecipe(
    id: 'claude',
    name: 'Claude Code',
    vendor: 'Anthropic',
    tagline: 'Agentic coding in your terminal',
    // Native musl build: libgcc/libstdc++. bash for its shell tool,
    // ripgrep for search, git for repositories.
    packages: ['bash', 'curl', 'git', 'libgcc', 'libstdc++', 'ripgrep', 'ca-certificates'],
    install: 'curl -fsSL https://claude.ai/install.sh | bash',
    command: 'claude',
  ),
  AgentRecipe(
    id: 'gemini',
    name: 'Gemini CLI',
    vendor: 'Google',
    tagline: 'Gemini models in your terminal',
    packages: ['nodejs', 'npm', 'git', 'bash', 'ripgrep', 'ca-certificates'],
    install: 'npm install -g @google/gemini-cli',
    command: 'gemini',
  ),
  AgentRecipe(
    id: 'codex',
    name: 'Codex CLI',
    vendor: 'OpenAI',
    tagline: 'OpenAI coding agent in your terminal',
    packages: ['nodejs', 'npm', 'git', 'bash', 'ripgrep', 'ca-certificates'],
    install: 'npm install -g @openai/codex',
    command: 'codex',
  ),
];
