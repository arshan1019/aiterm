/// Where new projects go by default (as the shell sees it).
const projectsFolder = '/root/projects';

/// [path] (as the shell sees it) is on the phone's shared storage, which
/// Linux sees at /sdcard with all-files access. It works, but has no
/// symlinks, executables or file modes.
bool onPhoneStorage(String path) =>
    path == '/sdcard' || path.startsWith('/sdcard/') || path.startsWith('/storage/') || path.startsWith('/mnt/sdcard/');

class Project {
  const Project({required this.id, required this.name, required this.path, required this.createdAt, required this.lastOpened, this.agentId});

  final String id;
  final String name;

  /// The folder, as the shell sees it (e.g. /root/projects/app).
  final String path;
  final DateTime createdAt;
  final DateTime lastOpened;

  /// The agent last opened here; the project's main button opens it.
  final String? agentId;

  Project copyWith({String? name, DateTime? lastOpened, String? agentId}) => Project(
        id: id,
        name: name ?? this.name,
        path: path,
        createdAt: createdAt,
        lastOpened: lastOpened ?? this.lastOpened,
        agentId: agentId ?? this.agentId,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'path': path,
        'created': createdAt.millisecondsSinceEpoch,
        'opened': lastOpened.millisecondsSinceEpoch,
        'agent': ?agentId,
      };

  static Project fromJson(Map<String, dynamic> j) => Project(
        id: j['id'] as String,
        name: j['name'] as String,
        path: j['path'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(j['created'] as int),
        lastOpened: DateTime.fromMillisecondsSinceEpoch(j['opened'] as int),
        agentId: j['agent'] as String?,
      );
}
