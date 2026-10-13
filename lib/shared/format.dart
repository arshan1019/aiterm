const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "just now", "5 min ago", "yesterday", "9 Mar 2025".
String timeAgo(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  if (d.inDays == 1) return 'yesterday';
  if (d.inDays < 7) return '${d.inDays} days ago';
  return '${t.day} ${_months[t.month - 1]} ${t.year}';
}

/// A guest path with the home folder shown as ~.
String shortPath(String path) {
  if (path == '/root') return '~';
  if (path.startsWith('/root/')) return '~${path.substring(5)}';
  return path;
}

String plural(int n, String one, [String? many]) => '$n ${n == 1 ? one : many ?? '${one}s'}';
