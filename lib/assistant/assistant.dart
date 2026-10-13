import 'commands.dart';
import 'needle.dart';
import 'tool_call.dart';

/// Answers "what do you want to do?". Exact phrasings are matched by rules
/// instantly and offline; anything else goes to the Needle model, which is
/// downloaded on first need.
class Assistant {
  Assistant(this.needle);

  final Needle needle;

  /// Suggestions for [request]. Returns null when the rules don't match and
  /// the model isn't downloaded yet, so the UI can offer the download.
  Future<List<Suggestion>?> suggest(String request, {required bool alpine}) async {
    if (matchRules(request) case final rule?) {
      return [?suggestionFor(rule, alpine: alpine, source: SuggestionSource.rules)];
    }
    if (!await needle.isDownloaded(Needle.textModel)) return null;
    return [
      for (final call in await needle.complete(request))
        ?suggestionFor(call, alpine: alpine, source: SuggestionSource.model),
    ];
  }
}
