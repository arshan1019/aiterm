// aiterm's file editor: CodeMirror 6 in a WebView, with an LSP client
// whose transport is the Flutter side (which runs the language server in
// Linux). Built into ../assets/editor/editor.js (npm run build).
//
// Flutter → editor: window.aiterm.open(options), .lspReceive(message),
//   .requestText(), .markSaved(), .undo(), .redo(), .search(), .setTheme(t)
// Editor → Flutter: AitermBridge.postMessage(JSON) with type
//   ready | changed {dirty} | text {text} | lsp {message} | save

import { basicSetup } from 'codemirror';
import { EditorState, Compartment } from '@codemirror/state';
import { EditorView, keymap } from '@codemirror/view';
import { indentWithTab, indentMore, undo, redo, cursorCharLeft, cursorCharRight, cursorLineUp, cursorLineDown } from '@codemirror/commands';
import { LanguageDescription, HighlightStyle, syntaxHighlighting, indentUnit } from '@codemirror/language';
import { languages } from '@codemirror/language-data';
import { openSearchPanel } from '@codemirror/search';
import { lintGutter } from '@codemirror/lint';
import { tags as t } from '@lezer/highlight';
import { LSPClient, languageServerExtensions } from '@codemirror/lsp-client';

const post = (msg) => {
  if (window.AitermBridge) window.AitermBridge.postMessage(JSON.stringify(msg));
};

const language = new Compartment();
const theme = new Compartment();
const lsp = new Compartment();

let view = null;
let saved = '';
let dirty = false;
let client = null;
let current = null; // the open() options
let pendingText = null;
const lspHandlers = new Set();

function palette(dark) {
  // The terminal's ANSI colours, so code looks the same everywhere.
  return dark
    ? { red: '#E2685A', green: '#6FBF73', yellow: '#D9B35C', blue: '#6C9EE5', magenta: '#B07CD1', cyan: '#5EC4A8' }
    : { red: '#C0392B', green: '#2E7D4F', yellow: '#9A6B00', blue: '#2F66C0', magenta: '#8E44AD', cyan: '#1F7F68' };
}

function appTheme(c, dark, fontSize) {
  const p = palette(dark);
  const ui = EditorView.theme(
    {
      '&': { color: c.text, backgroundColor: c.bg, height: '100%', fontSize: `${fontSize}px` },
      '.cm-scroller': { fontFamily: 'JetBrainsMono, monospace', lineHeight: '1.5' },
      '.cm-content': { caretColor: c.accent, padding: '8px 0' },
      '.cm-cursor, .cm-dropCursor': { borderLeftColor: c.accent, borderLeftWidth: '2px' },
      '&.cm-focused .cm-selectionBackground, .cm-selectionBackground, .cm-content ::selection': {
        backgroundColor: `${c.accent}55`,
      },
      '.cm-gutters': { backgroundColor: c.bg, color: c.textMuted, border: 'none' },
      '.cm-activeLineGutter': { backgroundColor: 'transparent', color: c.text },
      '.cm-activeLine': { backgroundColor: `${c.surface}` },
      '.cm-foldPlaceholder': { backgroundColor: c.surfaceAlt, border: 'none', color: c.textMuted },
      '.cm-panels': { backgroundColor: c.surface, color: c.text },
      '.cm-panels.cm-panels-top': { borderBottom: `1px solid ${c.border}` },
      '.cm-panels.cm-panels-bottom': { borderTop: `1px solid ${c.border}` },
      '.cm-panel input, .cm-panel button': { fontFamily: 'inherit', fontSize: '14px' },
      '.cm-textfield': { backgroundColor: c.surfaceAlt, color: c.text, border: 'none', borderRadius: '8px', padding: '6px 8px' },
      '.cm-button': {
        backgroundImage: 'none', backgroundColor: c.surfaceAlt, color: c.text,
        border: 'none', borderRadius: '8px', padding: '6px 10px',
      },
      '.cm-searchMatch': { backgroundColor: `${c.accent}40` },
      '.cm-searchMatch.cm-searchMatch-selected': { backgroundColor: `${c.accent}80` },
      '.cm-selectionMatch': { backgroundColor: `${c.accent}26` },
      '.cm-matchingBracket, &.cm-focused .cm-matchingBracket': { backgroundColor: `${c.accent}33`, outline: 'none' },
      '.cm-tooltip': { backgroundColor: c.surface, color: c.text, border: `1px solid ${c.border}`, borderRadius: '10px' },
      '.cm-tooltip-autocomplete > ul': { fontFamily: 'JetBrainsMono, monospace' },
      '.cm-tooltip-autocomplete > ul > li': { padding: '4px 8px' },
      '.cm-tooltip-autocomplete > ul > li[aria-selected]': { backgroundColor: `${c.accent}33`, color: c.text },
      '.cm-diagnostic': { padding: '6px 10px' },
      '.cm-diagnostic-error': { borderLeft: `3px solid ${c.danger}` },
      '.cm-diagnostic-warning': { borderLeft: `3px solid ${p.yellow}` },
      '.cm-lintRange-error': { backgroundImage: 'none', textDecoration: `underline wavy ${c.danger}`, textUnderlineOffset: '3px' },
      '.cm-lintRange-warning': { backgroundImage: 'none', textDecoration: `underline wavy ${p.yellow}`, textUnderlineOffset: '3px' },
      '.cm-lint-marker-error': { content: 'none' },
    },
    { dark },
  );
  const code = HighlightStyle.define([
    { tag: [t.keyword, t.controlKeyword, t.moduleKeyword, t.operatorKeyword, t.modifier], color: p.magenta },
    { tag: [t.string, t.special(t.string), t.regexp, t.character], color: p.green },
    { tag: [t.number, t.bool, t.null, t.atom], color: p.yellow },
    { tag: [t.comment, t.lineComment, t.blockComment, t.docComment], color: c.textMuted, fontStyle: 'italic' },
    { tag: [t.function(t.variableName), t.function(t.propertyName), t.macroName], color: p.blue },
    { tag: [t.typeName, t.className, t.namespace, t.tagName], color: p.cyan },
    { tag: [t.propertyName, t.attributeName], color: p.cyan },
    { tag: [t.definition(t.variableName), t.labelName], color: c.text },
    { tag: [t.meta, t.annotation, t.processingInstruction], color: p.yellow },
    { tag: [t.heading], color: p.blue, fontWeight: 'bold' },
    { tag: [t.emphasis], fontStyle: 'italic' },
    { tag: [t.strong], fontWeight: 'bold' },
    { tag: [t.link, t.url], color: p.cyan, textDecoration: 'underline' },
    { tag: [t.invalid], color: c.danger },
    { tag: [t.inserted], color: p.green },
    { tag: [t.deleted], color: p.red },
  ]);
  return [ui, syntaxHighlighting(code)];
}

function setDirty(value) {
  if (value === dirty) return;
  dirty = value;
  post({ type: 'changed', dirty });
}

async function loadLanguage(path) {
  const name = path.split('/').pop();
  const desc = LanguageDescription.matchFilename(languages, name);
  if (!desc) return [];
  try {
    return await desc.load();
  } catch (e) {
    return [];
  }
}

function connectLsp(options) {
  if (!options.lsp) return [];
  client = new LSPClient({
    rootUri: options.rootUri,
    extensions: languageServerExtensions(),
    timeout: 10000,
  });
  client.connect({
    send: (message) => post({ type: 'lsp', message }),
    subscribe: (h) => lspHandlers.add(h),
    unsubscribe: (h) => lspHandlers.delete(h),
  });
  return [client.plugin(options.uri, options.languageId), lintGutter()];
}

window.aiterm = {
  async open(options) {
    current = options;
    saved = options.text;
    dirty = false;
    const state = EditorState.create({
      doc: options.text,
      extensions: [
        basicSetup,
        keymap.of([
          indentWithTab,
          { key: 'Mod-s', run: () => (post({ type: 'save' }), true) },
        ]),
        indentUnit.of('  '),
        EditorState.tabSize.of(2),
        EditorView.lineWrapping,
        language.of([]),
        theme.of(appTheme(options.colors, options.dark, options.fontSize)),
        lsp.of([]),
        EditorState.readOnly.of(!!options.readOnly),
        EditorView.updateListener.of((u) => {
          if (u.docChanged) setDirty(u.state.doc.toString() !== saved);
        }),
      ],
    });
    if (view) view.destroy();
    view = new EditorView({ state, parent: document.getElementById('editor') });
    const lang = await loadLanguage(options.path);
    view.dispatch({ effects: language.reconfigure(lang) });
    view.dispatch({ effects: lsp.reconfigure(connectLsp(options)) });
  },

  /** An LSP message from the server. */
  lspReceive(message) {
    for (const h of lspHandlers) h(message);
  },

  /** The language server is ready now (installed after the file opened). */
  lspStart() {
    if (!view || !current) return;
    if (client) client.disconnect();
    view.dispatch({ effects: lsp.reconfigure(connectLsp({ ...current, lsp: true })) });
  },

  /** The language server stopped (or wasn't started): drop the client. */
  lspStop() {
    if (client) client.disconnect();
    client = null;
    if (view) view.dispatch({ effects: lsp.reconfigure([]) });
  },

  requestText() {
    pendingText = view ? view.state.doc.toString() : '';
    post({ type: 'text', text: pendingText });
  },

  /** The text last sent with requestText() is on disk now. */
  markSaved() {
    if (pendingText === null) return;
    saved = pendingText;
    pendingText = null;
    setDirty(view ? view.state.doc.toString() !== saved : false);
  },

  /** A key from the key row (phone keyboards have no Tab or arrows). */
  key(name) {
    if (!view) return;
    const run = { tab: indentMore, left: cursorCharLeft, right: cursorCharRight, up: cursorLineUp, down: cursorLineDown }[name];
    if (run) run(view);
    view.focus();
  },

  insert(text) {
    if (!view) return;
    view.dispatch(view.state.replaceSelection(text));
    view.focus();
  },

  undo() { if (view) undo(view); },
  redo() { if (view) redo(view); },
  search() { if (view) openSearchPanel(view); },

  setTheme(options) {
    if (view) view.dispatch({ effects: theme.reconfigure(appTheme(options.colors, options.dark, options.fontSize)) });
  },
};

post({ type: 'ready' });
