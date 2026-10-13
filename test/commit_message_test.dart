import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/git/commit_message.dart';
import 'package:aiterm/git/git_parsers.dart';

GitChange w(String path, GitChangeKind k, {String? from}) => GitChange(path: path, unstaged: k, origPath: from);
GitChange st(String path, GitChangeKind k) => GitChange(path: path, staged: k);

void main() {
  test('one file: a verb and its name', () {
    expect(suggestCommitMessage([w('lib/main.dart', GitChangeKind.modified)]), 'Update main.dart');
    expect(suggestCommitMessage([w('notes.txt', GitChangeKind.untracked)]), 'Add notes.txt');
    expect(suggestCommitMessage([w('old.txt', GitChangeKind.deleted)]), 'Delete old.txt');
    expect(suggestCommitMessage([st('b.txt', GitChangeKind.renamed)]), 'Rename b.txt');
  });

  test('mixed changes: added first, then updated, deleted', () {
    expect(
      suggestCommitMessage([w('README.md', GitChangeKind.modified), w('notes.txt', GitChangeKind.untracked)]),
      'Add notes.txt, update README.md',
    );
    expect(
      suggestCommitMessage([w('a.txt', GitChangeKind.modified), w('b.txt', GitChangeKind.modified), w('x', GitChangeKind.deleted)]),
      'Update a.txt and b.txt, delete x',
    );
  });

  test('many files of a kind are counted', () {
    expect(
      suggestCommitMessage([for (final f in ['a', 'b', 'c', 'd']) w('src/$f.ts', GitChangeKind.modified)]),
      'Update 4 files in src',
    );
    expect(
      suggestCommitMessage([w('a', GitChangeKind.added), w('lib/b', GitChangeKind.added), w('c/d', GitChangeKind.added)]),
      'Add 3 files',
    );
  });

  test('staged changes are what gets committed, so only they are described', () {
    expect(
      suggestCommitMessage([st('a.txt', GitChangeKind.added), w('b.txt', GitChangeKind.modified)]),
      'Add a.txt',
    );
  });

  test('nothing to describe', () => expect(suggestCommitMessage([]), ''));
}
