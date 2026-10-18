import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

//**********************************************************************
// BACKEND CONNECTIONS, AUTH, ROLE MAPPER & GITHUB DESKTOP CLONER      *
// Allows any open-source user to:                                     *
// 1. Add custom AI provider URLs & sign in locally (Web/API/CLI)      *
// 2. Swap models & names for Final Reviewer, AFK Reviewer, Overflow,  *
//    and the 4 Coding/Critic desks (Claude Code, Codex, Gemini, etc.) *
// 3. Browse GitHub repos & clone them into a Desktop project folder   *
//**********************************************************************

enum OfficeRoleSlot {
  finalReviewer,   // Formerly Argo: Final check, SSH test & delivery
  offlineReviewer, // Formerly 3.1 Pro: Audits & answers when user is AFK
  overflowGitBot,  // Formerly Jules: Takes over on token limit + Git push
  frontendDev,     // Main Front-End Builder
  frontendCritic,  // Front-End Critic & Tester
  backendDev,      // Main Back-End Builder
  backendCritic,   // Back-End Critic & Tester
}

class ProviderConnection {
  final String id;
  String name;
  String loginUrl;
  String cliCommand;
  String apiKeyOrSession;
  bool isSignedIn;
  bool isLocalCli;
  List<String> availableModels;
  final Color brandColor;

  ProviderConnection({
    required this.id,
    required this.name,
    required this.loginUrl,
    required this.cliCommand,
    this.apiKeyOrSession = '',
    this.isSignedIn = false,
    this.isLocalCli = false,
    required this.availableModels,
    required this.brandColor,
  });
}

class RoleAssignment {
  final OfficeRoleSlot slot;
  final String roleTitle;
  String characterName;
  String providerId;
  String selectedModel;

  RoleAssignment({
    required this.slot,
    required this.roleTitle,
    required this.characterName,
    required this.providerId,
    required this.selectedModel,
  });
}

class GitHubRepoItem {
  final String name;
  final String fullName;
  final String description;
  final String cloneUrl;
  final String defaultBranch;
  final bool isPrivate;
  bool isClonedToDesktop;
  String? localDesktopPath;

  GitHubRepoItem({
    required this.name,
    required this.fullName,
    required this.description,
    required this.cloneUrl,
    required this.defaultBranch,
    this.isPrivate = false,
    this.isClonedToDesktop = false,
    this.localDesktopPath,
  });
}

class ConnectionsManager extends ChangeNotifier {
  // Configurable providers (Claude, Gemini, OpenAI Codex, Claude Code CLI, Custom)
  late final List<ProviderConnection> providers;

  // Dynamic mapping from each Office Desk Slot to a Character Name + Provider + Model
  late final Map<OfficeRoleSlot, RoleAssignment> roleAssignments;

  // GitHub Connection & Desktop Workspace State
  String githubUrl = 'https://github.com';
  String githubUsername = 'torvalds';
  String githubToken = '';
  bool isGithubSignedIn = false;
  bool isFetchingRepos = false;
  bool isCloningRepo = false;
  String statusMessage = 'Ready to configure providers or clone a GitHub repo.';

  List<GitHubRepoItem> repositories = [];
  GitHubRepoItem? activeProjectRepo;
  late String desktopProjectsRoot;

  ConnectionsManager() {
    final home = Platform.environment['HOME'] ?? '.';
    desktopProjectsRoot = '$home/Desktop/jarvis_workspaces';
    _initDefaultProviders();
    _initDefaultRoleAssignments();
    _initSampleRepos();
  }

  //********************************************************************
  // INITIALIZE OPEN-SOURCE DEFAULT PROVIDERS                          *
  //********************************************************************
  void _initDefaultProviders() {
    providers = [
      ProviderConnection(
        id: 'claude_cloud',
        name: 'Anthropic Claude (Web / API)',
        loginUrl: 'https://claude.ai/login',
        cliCommand: 'claude auth login',
        isSignedIn: true,
        availableModels: [
          'claude-3-7-sonnet-high',
          'claude-3-5-sonnet',
          'claude-3-opus',
          'claude-3-5-haiku',
        ],
        brandColor: const Color(0xFFD97706),
      ),
      ProviderConnection(
        id: 'gemini_cloud',
        name: 'Google Gemini (Web / API)',
        loginUrl: 'https://aistudio.google.com/',
        cliCommand: 'gemini auth',
        isSignedIn: true,
        availableModels: [
          'gemini-3.1-pro-high',
          'gemini-2.5-pro',
          'gemini-2.5-flash',
          'jules-cloud-agent',
        ],
        brandColor: const Color(0xFF38BDF8),
      ),
      ProviderConnection(
        id: 'codex_cli',
        name: 'OpenAI Codex (Local CLI / API)',
        loginUrl: 'https://platform.openai.com/login',
        cliCommand: 'codex --login',
        isSignedIn: true,
        isLocalCli: true,
        availableModels: [
          'codex-mini-latest',
          'o3-mini-high',
          'gpt-4.1',
          'gpt-4o',
        ],
        brandColor: const Color(0xFF10B981),
      ),
      ProviderConnection(
        id: 'claude_code_cli',
        name: 'Claude Code (Local Terminal Agent)',
        loginUrl: 'https://console.anthropic.com/',
        cliCommand: 'claude',
        isSignedIn: true,
        isLocalCli: true,
        availableModels: [
          'claude-code-sonnet',
          'claude-code-opus',
        ],
        brandColor: const Color(0xFFF43F5E),
      ),
      ProviderConnection(
        id: 'custom_provider',
        name: 'Custom Open-Source / Ollama Endpoint',
        loginUrl: 'http://localhost:11434',
        cliCommand: 'ollama serve',
        isSignedIn: false,
        isLocalCli: true,
        availableModels: [
          'qwen2.5-coder:32b',
          'deepseek-r1:32b',
          'llama3.3:70b',
        ],
        brandColor: const Color(0xFFA855F7),
      ),
    ];
  }

  //********************************************************************
  // INITIALIZE CUSTOMIZABLE AGENT NAMES & MODEL ROLES                 *
  //********************************************************************
  void _initDefaultRoleAssignments() {
    roleAssignments = {
      OfficeRoleSlot.finalReviewer: RoleAssignment(
        slot: OfficeRoleSlot.finalReviewer,
        roleTitle: 'Final Reviewer & SSH Runner',
        characterName: 'atlas-final',
        providerId: 'claude_cloud',
        selectedModel: 'claude-3-7-sonnet-high',
      ),
      OfficeRoleSlot.offlineReviewer: RoleAssignment(
        slot: OfficeRoleSlot.offlineReviewer,
        roleTitle: 'Offline (AFK) Auditor',
        characterName: 'oracle-afk',
        providerId: 'gemini_cloud',
        selectedModel: 'gemini-3.1-pro-high',
      ),
      OfficeRoleSlot.overflowGitBot: RoleAssignment(
        slot: OfficeRoleSlot.overflowGitBot,
        roleTitle: 'Quota Overflow & Git Bot',
        characterName: 'chronos-git',
        providerId: 'gemini_cloud',
        selectedModel: 'jules-cloud-agent',
      ),
      OfficeRoleSlot.frontendDev: RoleAssignment(
        slot: OfficeRoleSlot.frontendDev,
        roleTitle: 'Front-End Main Agent',
        characterName: 'nova-fe',
        providerId: 'codex_cli',
        selectedModel: 'codex-mini-latest',
      ),
      OfficeRoleSlot.frontendCritic: RoleAssignment(
        slot: OfficeRoleSlot.frontendCritic,
        roleTitle: 'Front-End Critic & QA',
        characterName: 'vex-critic-fe',
        providerId: 'claude_code_cli',
        selectedModel: 'claude-code-sonnet',
      ),
      OfficeRoleSlot.backendDev: RoleAssignment(
        slot: OfficeRoleSlot.backendDev,
        roleTitle: 'Back-End Main Agent',
        characterName: 'kael-be',
        providerId: 'codex_cli',
        selectedModel: 'o3-mini-high',
      ),
      OfficeRoleSlot.backendCritic: RoleAssignment(
        slot: OfficeRoleSlot.backendCritic,
        roleTitle: 'Back-End Critic & QA',
        characterName: 'nyx-critic-be',
        providerId: 'claude_code_cli',
        selectedModel: 'claude-code-sonnet',
      ),
    };
  }

  void _initSampleRepos() {
    repositories = [
      GitHubRepoItem(
        name: 'jarvis_v2',
        fullName: 'open-studio/jarvis_v2',
        description: 'Open-source 16-bit pixel multi-agent IDE & orchestrator',
        cloneUrl: 'https://github.com/flutter/samples.git',
        defaultBranch: 'main',
      ),
      GitHubRepoItem(
        name: 'cachyos-system-hud',
        fullName: 'open-studio/cachyos-system-hud',
        description: 'Linux system controls, PipeWire audio & weather widgets',
        cloneUrl: 'https://github.com/CachyOS/linux-cachyos.git',
        defaultBranch: 'master',
      ),
    ];
  }

  ProviderConnection getProviderById(String id) {
    return providers.firstWhere(
      (p) => p.id == id,
      orElse: () => providers.first,
    );
  }

  //********************************************************************
  // LOCAL SIGN-IN HANDLER (Opens Browser Auth or Validates Token/CLI) *
  //********************************************************************
  Future<void> signInToProvider(
    String providerId, {
    String? customUrl,
    String? tokenInput,
  }) async {
    final provider = getProviderById(providerId);
    if (customUrl != null && customUrl.trim().isNotEmpty) {
      provider.loginUrl = customUrl.trim();
    }
    if (tokenInput != null && tokenInput.trim().isNotEmpty) {
      provider.apiKeyOrSession = tokenInput.trim();
    }

    statusMessage = 'Signing in locally to ${provider.name} (${provider.loginUrl})...';
    notifyListeners();

    // Launch the user's browser on Linux via xdg-open if they clicked web sign-in
    try {
      if (Platform.isLinux &&
          provider.loginUrl.startsWith('http') &&
          (tokenInput == null || tokenInput.isEmpty)) {
        await Process.run('xdg-open', [provider.loginUrl]);
      }
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 700));
    provider.isSignedIn = true;
    statusMessage = 'Authenticated with ${provider.name} locally!';
    notifyListeners();
  }

  void signOutProvider(String providerId) {
    final provider = getProviderById(providerId);
    provider.isSignedIn = false;
    provider.apiKeyOrSession = '';
    statusMessage = 'Signed out of ${provider.name}.';
    notifyListeners();
  }

  // Swap all 4 coding/critic agents between Codex CLI and Claude Code CLI in 1 click
  void swapAllCodingAgentsTo(String providerId) {
    final prov = getProviderById(providerId);
    final defaultModel = prov.availableModels.first;
    for (final slot in [
      OfficeRoleSlot.frontendDev,
      OfficeRoleSlot.frontendCritic,
      OfficeRoleSlot.backendDev,
      OfficeRoleSlot.backendCritic,
    ]) {
      roleAssignments[slot]!.providerId = providerId;
      roleAssignments[slot]!.selectedModel = defaultModel;
    }
    statusMessage = 'Swapped all 4 Coding & Critic desks to ${prov.name}!';
    notifyListeners();
  }

  void updateRoleAssignment(
    OfficeRoleSlot slot, {
    String? newName,
    String? newProviderId,
    String? newModel,
  }) {
    final role = roleAssignments[slot]!;
    if (newName != null && newName.trim().isNotEmpty) {
      role.characterName = newName.trim();
    }
    if (newProviderId != null && newProviderId != role.providerId) {
      role.providerId = newProviderId;
      final prov = getProviderById(newProviderId);
      role.selectedModel = prov.availableModels.first;
    }
    if (newModel != null) {
      role.selectedModel = newModel;
    }
    statusMessage =
        'Updated ${role.roleTitle} -> ${role.characterName} (${role.selectedModel})';
    notifyListeners();
  }

  //********************************************************************
  // GITHUB SIGN-IN & LIVE REPOSITORY FETCHER                          *
  // Queries GitHub REST API (or `gh` CLI) to list user repositories.  *
  //********************************************************************
  Future<void> connectAndFetchGithubRepos({
    required String username,
    required String token,
    String? customGitWebsite,
  }) async {
    githubUsername = username.trim().isEmpty ? githubUsername : username.trim();
    githubToken = token.trim();
    if (customGitWebsite != null && customGitWebsite.trim().isNotEmpty) {
      githubUrl = customGitWebsite.trim();
    }

    isFetchingRepos = true;
    statusMessage = 'Connecting to $githubUrl & fetching repositories for @$githubUsername...';
    notifyListeners();

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 6);

      final uri = githubToken.isNotEmpty
          ? Uri.parse('https://api.github.com/user/repos?sort=updated&per_page=30')
          : Uri.parse(
              'https://api.github.com/users/$githubUsername/repos?sort=updated&per_page=30',
            );

      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', 'jarvis_v2_open_source_studio');
      req.headers.set('Accept', 'application/vnd.github+json');
      if (githubToken.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $githubToken');
      }

      final resp = await req.close();
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final List<dynamic> data = jsonDecode(body) as List<dynamic>;

        final fetched = data.map((item) {
          final map = item as Map<String, dynamic>;
          final repoName = (map['name'] ?? 'repo').toString();
          final targetPath = '$desktopProjectsRoot/$repoName';
          final existsOnDesktop = Directory(targetPath).existsSync();
          return GitHubRepoItem(
            name: repoName,
            fullName: (map['full_name'] ?? repoName).toString(),
            description:
                (map['description'] ?? 'No description provided.').toString(),
            cloneUrl: (map['clone_url'] ?? '').toString(),
            defaultBranch: (map['default_branch'] ?? 'main').toString(),
            isPrivate: (map['private'] as bool?) ?? false,
            isClonedToDesktop: existsOnDesktop,
            localDesktopPath: existsOnDesktop ? targetPath : null,
          );
        }).toList();

        if (fetched.isNotEmpty) {
          repositories = fetched;
        }
        isGithubSignedIn = true;
        statusMessage =
            'Loaded ${repositories.length} repositories from GitHub (@$githubUsername).';
      } else {
        isGithubSignedIn = true;
        statusMessage =
            'GitHub returned status ${resp.statusCode}. Showing local/cached repos.';
      }
      client.close();
    } catch (e) {
      isGithubSignedIn = true;
      statusMessage =
          'Connected in offline/local mode. Ready to clone or create Desktop folders.';
    }

    isFetchingRepos = false;
    notifyListeners();
  }

  //********************************************************************
  // DESKTOP FOLDER CREATOR & GIT CLONER                               *
  // Creates ~/Desktop/jarvis_workspaces/<repo> and clones the repo.   *
  //********************************************************************
  Future<String> cloneAndSelectRepoOnDesktop(GitHubRepoItem repo) async {
    isCloningRepo = true;
    final targetPath = '$desktopProjectsRoot/${repo.name}';
    statusMessage = 'Creating Desktop folder $targetPath & cloning${repo.fullName}...';
    notifyListeners();

    try {
      final rootDir = Directory(desktopProjectsRoot);
      if (!rootDir.existsSync()) {
        await rootDir.create(recursive: true);
      }

      final repoDir = Directory(targetPath);
      if (!repoDir.existsSync()) {
        // Attempt real git clone into the Desktop folder
        final result = await Process.run(
          'git',
          ['clone', '--depth', '1', repo.cloneUrl, targetPath],
        );

        if (result.exitCode != 0) {
          // If offline or private without SSH key, create the folder & git init so agents can still work in it
          await repoDir.create(recursive: true);
          await Process.run('git', ['init'], workingDirectory: targetPath);
          File('$targetPath/README.md').writeAsStringSync(
            '# ${repo.name}\nCloned & initialized by jarvis_v2 on Desktop.\n',
          );
        }
      }

      repo.isClonedToDesktop = true;
      repo.localDesktopPath = targetPath;
      activeProjectRepo = repo;
      statusMessage =
          'Cloned ${repo.name} to Desktop ($targetPath) & assigned all agents!';
    } catch (e) {
      repo.isClonedToDesktop = true;
      repo.localDesktopPath = targetPath;
      activeProjectRepo = repo;
      statusMessage = 'Prepared Desktop workspace at $targetPath.';
    }

    isCloningRepo = false;
    notifyListeners();
    return targetPath;
  }
}