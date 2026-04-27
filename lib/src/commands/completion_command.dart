import 'package:args/args.dart';

import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../cli/runner.dart';
import '../model/manifest/loader_ref.dart';

class CompletionCommand extends GitrinthCommand {
  @override
  String get name => 'completion';

  @override
  String get description =>
      'Emit a shell-completion script for the given shell.';

  @override
  String get invocation => 'gitrinth completion <bash|zsh|fish|powershell>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw const UsageError(
        'completion requires a shell: '
        'gitrinth completion <bash|zsh|fish|powershell>',
      );
    }
    if (rest.length > 1) {
      throw UsageError(
        'Unexpected arguments after shell: ${rest.skip(1).join(' ')}',
      );
    }
    final shell = rest.first;
    final model = _buildModel(gitrinthRunner);
    final String script;
    switch (shell) {
      case 'bash':
        script = _emitBash(model);
      case 'zsh':
        script = _emitZsh(model);
      case 'fish':
        script = _emitFish(model);
      case 'powershell':
      case 'pwsh':
        script = _emitPowerShell(model);
      default:
        throw UsageError(
          'Unknown shell: $shell. '
          'Expected bash, zsh, fish, or powershell.',
        );
    }
    console.raw(script);
    return exitOk;
  }
}

// ---------------------------------------------------------------------------
// Intermediate representation
// ---------------------------------------------------------------------------

class _CompletionModel {
  final String executable;
  final List<_OptionSpec> globalOptions;
  final List<_CommandSpec> commands;
  _CompletionModel(this.executable, this.globalOptions, this.commands);
}

class _CommandSpec {
  final String name;
  final String description;
  final List<_OptionSpec> options;
  _CommandSpec(this.name, this.description, this.options);
}

class _OptionSpec {
  final String name;
  final String? abbr;
  final String description;
  final bool isFlag;
  final bool negatable;
  final List<String>? allowed;
  _OptionSpec({
    required this.name,
    required this.abbr,
    required this.description,
    required this.isFlag,
    required this.negatable,
    required this.allowed,
  });
}

_CompletionModel _buildModel(GitrinthRunner runner) {
  final globals = _collectOptions(runner.argParser);
  final commands = <_CommandSpec>[];
  for (final entry in runner.commands.entries) {
    final cmd = entry.value;
    // Skip aliases (entry.key != cmd.name) and hidden commands (e.g. 'help').
    if (entry.key != cmd.name) continue;
    if (cmd.hidden) continue;
    commands.add(
      _CommandSpec(
        cmd.name,
        _firstLine(cmd.description),
        _collectOptions(cmd.argParser),
      ),
    );
  }
  commands.sort((a, b) => a.name.compareTo(b.name));
  return _CompletionModel(runner.executableName, globals, commands);
}

List<_OptionSpec> _collectOptions(ArgParser parser) {
  final out = <_OptionSpec>[];
  for (final opt in parser.options.values) {
    if (opt.name == 'help') continue;
    if (opt.hide) continue;
    out.add(
      _OptionSpec(
        name: opt.name,
        abbr: opt.abbr,
        description: _firstLine(opt.help ?? ''),
        isFlag: opt.isFlag,
        negatable: opt.negatable ?? false,
        allowed: opt.allowed?.toList(),
      ),
    );
  }
  out.sort((a, b) => a.name.compareTo(b.name));
  return out;
}

String _firstLine(String s) {
  final nl = s.indexOf('\n');
  final head = nl < 0 ? s : s.substring(0, nl);
  return head.trim();
}

/// Manual completion candidates for options whose `argParser.allowed`
/// can't be set (because the option accepts a richer grammar than a
/// fixed enum). The bare names are still useful as completion hints
/// even when the user can append `:<tag>` after one. Keyed by option
/// name so any subcommand declaring that option picks up the same
/// candidate set automatically.
final Map<String, List<String>> _manualEnumHints = {
  // `--loader` accepts `<name>` or `<name>:<tag>` per
  // [parseLoaderRef]; the shared name list is the canonical source.
  'loader': loaderRefNames,
};

/// Map of option-name -> allowed-values across globals and all subcommands.
/// Used so `gitrinth <anything> --env <TAB>` always completes to the same set.
Map<String, List<String>> _enumOptions(_CompletionModel m) {
  final out = <String, List<String>>{};
  void collect(Iterable<_OptionSpec> opts) {
    for (final o in opts) {
      final allowed = o.allowed ?? _manualEnumHints[o.name];
      if (allowed != null && allowed.isNotEmpty) {
        out[o.name] = allowed;
      }
    }
  }

  collect(m.globalOptions);
  for (final c in m.commands) {
    collect(c.options);
  }
  return out;
}

/// All flag spellings a command (or the global scope) accepts, in the form
/// shells can offer for completion: `--name`, `--no-name` for negatable
/// flags, and `-x` for abbreviations.
List<String> _flagSpellings(List<_OptionSpec> opts) {
  final out = <String>[];
  for (final o in opts) {
    out.add('--${o.name}');
    if (o.isFlag && o.negatable) {
      out.add('--no-${o.name}');
    }
    if (o.abbr != null) {
      out.add('-${o.abbr}');
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Shell-specific emitters. Each consumes the same _CompletionModel and
// produces a self-contained script written to stdout.
// ---------------------------------------------------------------------------

String _sqEscape(String s) => s.replaceAll("'", r"'\''");
String _pwshEscape(String s) => s.replaceAll("'", "''");

String _emitBash(_CompletionModel m) {
  final exe = m.executable;
  final sb = StringBuffer();
  final subcmds = m.commands.map((c) => c.name).join(' ');
  final globals = [..._flagSpellings(m.globalOptions), '--help'].join(' ');
  final enums = _enumOptions(m);

  sb.writeln('# bash completion for $exe');
  sb.writeln('# Source this file, or install to your bash-completion dir.');
  sb.writeln('_${exe}_completion() {');
  sb.writeln('  local cur prev');
  sb.writeln('  COMPREPLY=()');
  sb.writeln(r'  cur="${COMP_WORDS[COMP_CWORD]}"');
  sb.writeln(r'  prev="${COMP_WORDS[COMP_CWORD-1]}"');
  sb.writeln('');
  sb.writeln('  # Locate the subcommand: first non-flag word after the exe.');
  sb.writeln('  local cmd=""');
  sb.writeln('  local i');
  sb.writeln(r'  for ((i=1; i<COMP_CWORD; i++)); do');
  sb.writeln(r'    case "${COMP_WORDS[i]}" in');
  sb.writeln('      -*) ;;');
  sb.writeln(r'      *) cmd="${COMP_WORDS[i]}"; break ;;');
  sb.writeln('    esac');
  sb.writeln('  done');
  sb.writeln('');
  if (enums.isNotEmpty) {
    sb.writeln('  # Enum-valued options: completion follows `--opt`.');
    sb.writeln(r'  case "$prev" in');
    for (final e in enums.entries) {
      final values = e.value.join(' ');
      sb.writeln(
        '    --${e.key}) '
        r'COMPREPLY=($(compgen -W "'
        '$values'
        r'" -- "$cur")); return ;;',
      );
    }
    sb.writeln('  esac');
    sb.writeln('');
  }
  sb.writeln(r'  if [[ -z "$cmd" ]]; then');
  sb.writeln(
    r'    COMPREPLY=($(compgen -W "'
    '$subcmds $globals'
    r'" -- "$cur"))',
  );
  sb.writeln('    return');
  sb.writeln('  fi');
  sb.writeln('');
  sb.writeln(r'  case "$cmd" in');
  for (final c in m.commands) {
    final names = [..._flagSpellings(c.options), '--help'].join(' ');
    sb.writeln('    ${c.name})');
    if (c.name == 'completion') {
      sb.writeln(r'      if [[ "$prev" == "completion" ]]; then');
      sb.writeln(
        r'        COMPREPLY=($(compgen -W "bash zsh fish powershell" '
        r'-- "$cur"))',
      );
      sb.writeln('        return');
      sb.writeln('      fi');
    }
    sb.writeln(
      r'      COMPREPLY=($(compgen -W "'
      '$names'
      r'" -- "$cur"))',
    );
    sb.writeln('      ;;');
  }
  sb.writeln('  esac');
  sb.writeln('}');
  sb.writeln('complete -F _${exe}_completion $exe');
  return sb.toString();
}

String _emitZsh(_CompletionModel m) {
  final exe = m.executable;
  final sb = StringBuffer();
  final enums = _enumOptions(m);

  sb.writeln('#compdef $exe');
  sb.writeln('# zsh completion for $exe');
  sb.writeln('');
  sb.writeln('_$exe() {');
  sb.writeln('  local -a commands');
  sb.writeln('  commands=(');
  for (final c in m.commands) {
    sb.writeln("    '${c.name}:${_sqEscape(c.description)}'");
  }
  sb.writeln('  )');
  sb.writeln('');
  sb.writeln('  local context state line');
  sb.writeln('  _arguments -C \\');
  sb.writeln("    '1: :->cmd' \\");
  sb.writeln("    '*:: :->args'");
  sb.writeln('');
  sb.writeln(r'  case "$state" in');
  sb.writeln('    cmd)');
  sb.writeln("      _describe -t commands '$exe command' commands");
  sb.writeln('      ;;');
  sb.writeln('    args)');
  sb.writeln(r'      case "$line[1]" in');
  for (final c in m.commands) {
    sb.writeln('        ${c.name})');
    if (c.name == 'completion') {
      sb.writeln(
        "          _values 'shell' "
        "'bash[Bash script]' 'zsh[Zsh script]' "
        "'fish[Fish script]' 'powershell[PowerShell script]'",
      );
    }
    if (c.options.isEmpty) {
      sb.writeln('          ;;');
      continue;
    }
    sb.writeln('          _arguments \\');
    final specs = <String>[];
    for (final o in c.options) {
      specs.add(_zshArgSpec(o, enums));
      if (o.isFlag && o.negatable) {
        specs.add("'--no-${o.name}[${_sqEscape(o.description)}]'");
      }
    }
    for (var i = 0; i < specs.length; i++) {
      final last = i == specs.length - 1;
      sb.writeln('            ${specs[i]}${last ? '' : ' \\'}');
    }
    sb.writeln('          ;;');
  }
  sb.writeln('      esac');
  sb.writeln('      ;;');
  sb.writeln('  esac');
  sb.writeln('}');
  sb.writeln('');
  sb.writeln(r'_' + exe + r' "$@"');
  return sb.toString();
}

String _zshArgSpec(_OptionSpec o, Map<String, List<String>> enums) {
  final desc = _sqEscape(o.description);
  if (o.isFlag) {
    if (o.abbr != null) {
      return "'(-${o.abbr} --${o.name})'{-${o.abbr},--${o.name}}'[$desc]'";
    }
    return "'--${o.name}[$desc]'";
  }
  // Value-taking option.
  final allowed = o.allowed ?? enums[o.name];
  final action = allowed != null ? '(${allowed.join(' ')})' : '_files';
  if (o.abbr != null) {
    return "'(-${o.abbr} --${o.name})'"
        "{-${o.abbr},--${o.name}}"
        "'[$desc]:${o.name}:$action'";
  }
  return "'--${o.name}[$desc]:${o.name}:$action'";
}

String _emitFish(_CompletionModel m) {
  final exe = m.executable;
  final sb = StringBuffer();
  final enums = _enumOptions(m);

  sb.writeln('# fish completion for $exe');
  sb.writeln('complete -c $exe -f');
  sb.writeln('');
  sb.writeln('# Global options');
  for (final o in m.globalOptions) {
    sb.writeln(_fishGlobalLine(exe, o, enums));
  }
  sb.writeln('');
  sb.writeln('# Subcommands');
  for (final c in m.commands) {
    final desc = _sqEscape(c.description);
    sb.writeln(
      "complete -c $exe -n '__fish_use_subcommand' -a '${c.name}' "
      "-d '$desc'",
    );
  }
  sb.writeln('');
  for (final c in m.commands) {
    if (c.options.isEmpty && c.name != 'completion') continue;
    sb.writeln('# ${c.name}');
    if (c.name == 'completion') {
      sb.writeln(
        "complete -c $exe -n '__fish_seen_subcommand_from completion' "
        "-xa 'bash zsh fish powershell'",
      );
    }
    for (final o in c.options) {
      sb.writeln(_fishCmdLine(exe, c.name, o, enums));
    }
    sb.writeln('');
  }
  return sb.toString();
}

String _fishGlobalLine(
  String exe,
  _OptionSpec o,
  Map<String, List<String>> enums,
) {
  final parts = <String>['complete', '-c', exe, '-l', o.name];
  if (o.abbr != null) parts.addAll(['-s', o.abbr!]);
  if (!o.isFlag) {
    final allowed = o.allowed ?? enums[o.name];
    if (allowed != null) {
      parts.addAll(['-xa', "'${allowed.join(' ')}'"]);
    } else {
      parts.add('-r');
    }
  }
  if (o.description.isNotEmpty) {
    parts.addAll(['-d', "'${_sqEscape(o.description)}'"]);
  }
  return parts.join(' ');
}

String _fishCmdLine(
  String exe,
  String cmd,
  _OptionSpec o,
  Map<String, List<String>> enums,
) {
  final parts = <String>[
    'complete',
    '-c',
    exe,
    '-n',
    "'__fish_seen_subcommand_from $cmd'",
    '-l',
    o.name,
  ];
  if (o.abbr != null) parts.addAll(['-s', o.abbr!]);
  if (!o.isFlag) {
    final allowed = o.allowed ?? enums[o.name];
    if (allowed != null) {
      parts.addAll(['-xa', "'${allowed.join(' ')}'"]);
    } else {
      parts.add('-r');
    }
  }
  if (o.description.isNotEmpty) {
    parts.addAll(['-d', "'${_sqEscape(o.description)}'"]);
  }
  return parts.join(' ');
}

String _emitPowerShell(_CompletionModel m) {
  final exe = m.executable;
  final sb = StringBuffer();
  final enums = _enumOptions(m);

  sb.writeln('# PowerShell completion for $exe');
  sb.writeln(
    'Register-ArgumentCompleter -Native -CommandName $exe -ScriptBlock {',
  );
  sb.writeln(r'  param($wordToComplete, $commandAst, $cursorPosition)');
  sb.writeln('');

  sb.writeln(r'  $commands = @{');
  for (final c in m.commands) {
    sb.writeln("    '${c.name}' = '${_pwshEscape(c.description)}'");
  }
  sb.writeln('  }');
  sb.writeln('');

  sb.writeln(r'  $commandFlags = @{');
  for (final c in m.commands) {
    final names = [
      ..._flagSpellings(c.options),
      '--help',
    ].map((s) => "'$s'").join(',');
    sb.writeln("    '${c.name}' = @($names)");
  }
  sb.writeln('  }');
  sb.writeln('');

  sb.writeln(r'  $enums = @{');
  enums.forEach((k, v) {
    final vals = v.map((s) => "'${_pwshEscape(s)}'").join(',');
    sb.writeln("    '$k' = @($vals)");
  });
  sb.writeln('  }');
  sb.writeln('');

  sb.writeln(r'  $globalFlags = @(');
  final globals = [..._flagSpellings(m.globalOptions), '--help'];
  sb.writeln('    ${globals.map((s) => "'$s'").join(',')}');
  sb.writeln('  )');
  sb.writeln('');

  sb.writeln(
    r'''  $tokens = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
  $cmd = $null
  for ($i = 1; $i -lt $tokens.Count; $i++) {
    $t = $tokens[$i]
    if ($t -notlike '-*' -and $commands.ContainsKey($t)) { $cmd = $t; break }
  }

  $prev = ''
  if ($cursorPosition -gt 0 -and $tokens.Count -ge 1) {
    $tail = if ($wordToComplete) { $tokens.Count - 2 } else { $tokens.Count - 1 }
    if ($tail -ge 0) { $prev = $tokens[$tail] }
  }

  if ($prev -like '--*') {
    $key = $prev.Substring(2)
    if ($enums.ContainsKey($key)) {
      $enums[$key] | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
      }
      return
    }
  }

  if (-not $cmd) {
    $commands.Keys | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
      [System.Management.Automation.CompletionResult]::new($_, $_, 'Command', $commands[$_])
    }
    $globalFlags | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
      [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_)
    }
    return
  }

  if ($cmd -eq 'completion' -and $prev -eq 'completion') {
    @('bash','zsh','fish','powershell') | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
      [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
    return
  }

  if ($commandFlags.ContainsKey($cmd)) {
    $commandFlags[$cmd] | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
      [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_)
    }
  }
}''',
  );
  sb.writeln('');
  return sb.toString();
}
