class Project {
  const Project({required this.id, required this.name, required this.path, required this.createdAt, required this.lastOpened});

  final String id;
  final String name;

  /// The folder, as the shell sees it (e.g. /root/projects/app).
  final String path;
  final DateTime createdAt;
  final DateTime lastOpened;

  Project copyWith({String? name, DateTime? lastOpened}) => Project(
        id: id,
        name: name ?? this.name,
        path: path,
        createdAt: createdAt,
        lastOpened: lastOpened ?? this.lastOpened,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'path': path,
        'created': createdAt.millisecondsSinceEpoch,
        'opened': lastOpened.millisecondsSinceEpoch,
      };

  static Project fromJson(Map<String, dynamic> j) => Project(
        id: j['id'] as String,
        name: j['name'] as String,
        path: j['path'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(j['created'] as int),
        lastOpened: DateTime.fromMillisecondsSinceEpoch(j['opened'] as int),
      );
}
